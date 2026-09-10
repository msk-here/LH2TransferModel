function varargout = refpropm(prop, spec1, value1, spec2, value2, varargin)
%REFPROPM  CoolProp shim - INSTRUMENTED BUILD (validation runs only).
%
%   Functionally identical to the production refpropm.m - INCLUDING the
%   saturation-boundary phase resolution and the '|liquid' / '|gas' phase
%   hint - but records every call and every failure so a run can be
%   audited afterwards.
%
%   Exists to answer a question a completed run cannot answer on its own:
%   did any property call FAIL and get swallowed by one of the upstream
%   try/catch blocks in LH2Simulate_Pump.m (lines 184-197, 254-267,
%   659-665, 1120-1131)? Those catches substitute fallback values
%   silently, so a model can run to completion, or merely appear slow,
%   while thousands of property calls fail invisibly.
%
%   USAGE
%       refpropm('log','on',    0,'',0,'');   % start logging (clears counters)
%       ... run MAIN ...
%       refpropm('log','report',0,'',0,'');   % print summary
%       refpropm('log','save',  0,'',0,'');   % write refpropm_log.mat
%       refpropm('log','off',   0,'',0,'');   % stop
%
%   Logging is OFF by default, so this file behaves exactly like the
%   production shim if you forget to enable it. It is slower than the
%   production build - restore refpropm.m afterwards.

persistent LOGGING CALLS FAILS NCALL NFAIL EXTREMA

% MAIN.m line 10 is "clear all", which clears functions from memory and so
% resets every persistent variable here. The logging flag is therefore ALSO
% kept in root application data, which "clear all" does not touch. If the
% persistents have been wiped, recover the request and re-initialise the
% counters. All property calls of interest happen after the clear, so
% nothing is lost by re-initialising at this point.
if isempty(LOGGING)
    if isappdata(0,'refpropm_logging') && getappdata(0,'refpropm_logging')
        LOGGING = true;
        CALLS = cell(0,1); FAILS = cell(0,1);
        NCALL = containers.Map('KeyType','char','ValueType','double');
        NFAIL = containers.Map('KeyType','char','ValueType','double');
        EXTREMA = containers.Map('KeyType','char','ValueType','any');
    else
        LOGGING = false;
    end
end

%% ------------------------------------------------------------------ %%
%% Logging control interface
%% ------------------------------------------------------------------ %%
if strcmpi(prop,'log')
    switch lower(spec1)
        case 'on'
            LOGGING = true;
            setappdata(0,'refpropm_logging',true);   % survives "clear all"
            CALLS = cell(0,1); FAILS = cell(0,1);
            NCALL = containers.Map('KeyType','char','ValueType','double');
            NFAIL = containers.Map('KeyType','char','ValueType','double');
            EXTREMA = containers.Map('KeyType','char','ValueType','any');
            fprintf('[refpropm] logging ON (survives the clear all in MAIN.m)\n');
        case 'off'
            LOGGING = false;
            setappdata(0,'refpropm_logging',false);
            fprintf('[refpropm] logging OFF\n');
        case 'report'
            local_report(NCALL, NFAIL, FAILS, EXTREMA);
        case 'save'
            log.calls = CALLS; log.fails = FAILS;
            log.ncall = NCALL; log.nfail = NFAIL; log.extrema = EXTREMA;
            save('refpropm_log.mat','log');
            fprintf('[refpropm] wrote refpropm_log.mat\n');
        otherwise
            error('refpropm:badLogCmd','Unknown log command ''%s''.', spec1);
    end
    if nargout > 0, varargout{1} = []; end
    return
end

%% ------------------------------------------------------------------ %%
%% Normal operation
%% ------------------------------------------------------------------ %%
key = sprintf('%s(%s,%s)', lower(prop), lower(strtrim(spec1)), lower(strtrim(spec2)));

if LOGGING
    if ~isKey(NCALL,key), NCALL(key) = 0; end
    NCALL(key) = NCALL(key) + 1;
    local_track(EXTREMA, lower(strtrim(spec1)), value1);
    local_track(EXTREMA, lower(strtrim(spec2)), value2);
end

try
    [varargout{1:max(nargout,1)}] = local_core(prop, spec1, value1, spec2, value2, varargin{:});
catch ME
    if LOGGING
        if ~isKey(NFAIL,key), NFAIL(key) = 0; end
        NFAIL(key) = NFAIL(key) + 1;
        FAILS{end+1,1} = struct('key',key,'prop',prop, ...
            'spec1',spec1,'value1',value1,'spec2',spec2,'value2',value2, ...
            'fluid',varargin{1},'msg',ME.message);
    end
    rethrow(ME);
end
end


%% ==================================================================== %%
function local_track(EXTREMA, spec, val)
if ~isnumeric(val) || ~isscalar(val) || ~isfinite(val), return; end
if ~isKey(EXTREMA,spec)
    EXTREMA(spec) = [val val];
else
    e = EXTREMA(spec);
    EXTREMA(spec) = [min(e(1),val) max(e(2),val)];
end
end


%% ==================================================================== %%
function local_report(NCALL, NFAIL, FAILS, EXTREMA)
fprintf('\n=====================================================\n');
fprintf(' refpropm call audit\n');
fprintf('=====================================================\n');
if isempty(NCALL) || NCALL.Count == 0
    fprintf(' No calls recorded.\n\n');
    if isappdata(0,'refpropm_logging') && getappdata(0,'refpropm_logging')
        fprintf('  Logging IS enabled, but no property calls have been seen\n');
        fprintf('  since it was switched on. Did the run actually execute?\n');
    else
        fprintf('  Logging was not enabled when the run executed.\n');
        fprintf('  Switch it on with:  refpropm(''log'',''on'',0,'''',0,'''');\n');
    end
    fprintf('=====================================================\n');
    return
end
k = keys(NCALL); tot = 0; totf = 0;
fprintf('\n%-22s %12s %10s\n','call shape','calls','FAILURES');
for i = 1:numel(k)
    n = NCALL(k{i});
    f = 0; if isKey(NFAIL,k{i}), f = NFAIL(k{i}); end
    tot = tot + n; totf = totf + f;
    flag = ''; if f > 0, flag = '   <-- FAILED'; end
    fprintf('%-22s %12d %10d%s\n', k{i}, n, f, flag);
end
fprintf('%-22s %12d %10d\n','TOTAL',tot,totf);

fprintf('\nInput ranges actually requested:\n');
ek = keys(EXTREMA);
for i = 1:numel(ek)
    e = EXTREMA(ek{i});
    fprintf('   %-4s  %14.6g  ..  %14.6g\n', ek{i}, e(1), e(2));
end

if totf == 0
    fprintf('\n  RESULT: zero property-call failures across %d calls.\n', tot);
    fprintf('  No upstream try/catch block was triggered by a CoolProp failure.\n');
else
    fprintf('\n  RESULT: %d FAILURES. First few:\n', totf);
    for i = 1:min(10,numel(FAILS))
        f = FAILS{i};
        fprintf('   %s at %s=%.8g, %s=%.8g (%s)\n     %s\n', ...
            f.key, f.spec1, f.value1, f.spec2, f.value2, f.fluid, f.msg);
    end
    fprintf('\n  These were swallowed by upstream try/catch blocks if the run\n');
    fprintf('  completed. Results are NOT trustworthy until each is explained.\n');
end
fprintf('=====================================================\n');
end


%% ==================================================================== %%
%% Core = the production shim, unchanged (incl. saturation phase fix)
%% ==================================================================== %%
function varargout = local_core(prop, spec1, value1, spec2, value2, varargin)
%REFPROPM  Drop-in CoolProp replacement for the NIST REFPROP MATLAB wrapper.
%
%   Implements the subset of refpropm.m needed by the LH2 transfer model
%   family (Osipov/Petitpas -> LLNL/LH2Transfer -> Gil LH2TransferModel),
%   backed by CoolProp through the MATLAB<->Python bridge.
%
%   USAGE (identical to NIST refpropm.m):
%       val = refpropm(prop, spec1, value1, spec2, value2, fluid)
%       [a,b] = refpropm('AB', spec1, value1, spec2, value2, fluid)
%       val = refpropm(prop, 'C', 0, ' ', 0, fluid)   % critical point
%       val = refpropm(prop, 'R', 0, ' ', 0, fluid)   % triple point
%
%   UNITS -- these follow NIST refpropm.m exactly, NOT CoolProp:
%       P   pressure          [kPa]     (CoolProp uses Pa; converted here)
%       V   dynamic viscosity [Pa*s]    (NOT uPa*s -- see note below)
%       M   molar mass        [g/mol]   (CoolProp uses kg/mol)
%       T [K]  D [kg/m^3]  H,U [J/kg]  S,C,O [J/(kg K)]  L [W/(m K)]
%       B [1/K]  Y [J/kg]  Q [kg/kg]  ^ [-]  A [m/s]  K [-]  Z [-]
%
%   VISCOSITY UNIT NOTE (verified, do not "fix" this):
%       NIST refpropm.m line ~648 returns {eta*1e-6}, i.e. Pa*s, and its
%       own header documents "V  Dynamic viscosity [Pa*s]". The LH2 model
%       agrees: Parameters_*.m hardcode mu_L = 13.54e-6 and mu_v = 0.98e-6
%       labelled [Pa*s]. CoolProp's 'viscosity' is already Pa*s, so NO
%       conversion is applied. Multiplying by 1e6 here would inflate every
%       Rayleigh number by 1e6 and silently produce plausible-looking but
%       wrong figures.
%
%   QUALITY FLAGS:
%       NIST refpropm lowercases the property request (line 328:
%       propReq = lower(varargin{1})), so 'q' and 'Q' are THE SAME CODE.
%       For 0 < q < 1 it returns mass quality; outside the dome it passes
%       REFPROP's raw flag through. This shim reproduces that convention:
%           -998  subcooled liquid
%            998  superheated vapour
%            999  supercritical
%       The models only ever test (q > 0 && q < 1), so any out-of-dome
%       value routes identically -- but matching REFPROP keeps debugging
%       output readable.
%
%   PHILOSOPHY: loud failure, never a silent fallback. Every error names
%   the property, the state and the fluid. No default/NaN returns.
%
%   Requires: pyenv configured, CoolProp importable from Python.
%   Self-contained: no other files from this repo are needed.

%% ------------------------------------------------------------------ %%
%% Options
%% ------------------------------------------------------------------ %%
CACHE_ENABLED = false;   % leave false until correctness is established.
                         % See "Memoisation" at the bottom of this file.

persistent cacheMap
if CACHE_ENABLED && isempty(cacheMap)
    cacheMap = containers.Map('KeyType','char','ValueType','double');
end

%% ------------------------------------------------------------------ %%
%% Argument handling
%% ------------------------------------------------------------------ %%
narginchk(6, inf);

if numel(varargin) > 1
    error('refpropm:mixtureUnsupported', ...
        ['This CoolProp shim supports pure fluids only; %d fluid ' ...
         'arguments were supplied. Mixtures are not implemented.'], numel(varargin));
end

fluid = local_mapFluid(varargin{1});

% refpropm lowercases the request; reproduce that so 'q' == 'Q'.
prop  = lower(prop);
spec1 = lower(strtrim(spec1));
spec2 = lower(strtrim(spec2));

nProp = numel(prop);
if nargout > nProp
    error('refpropm:tooManyOutputs', ...
        'Requested %d outputs but property string ''%s'' has %d characters.', ...
        nargout, prop, nProp);
end
varargout = cell(1, max(nargout, 1));

%% ------------------------------------------------------------------ %%
%% Fixed-point calls: 'C' critical, 'R' triple, 'M' max
%% ------------------------------------------------------------------ %%
if any(strcmp(spec1, {'c','r','m'}))
    for i = 1:max(nargout,1)
        varargout{i} = local_fixedPoint(prop(i), spec1, fluid);
    end
    return
end

%% ------------------------------------------------------------------ %%
%% Build the CoolProp input pair
%% ------------------------------------------------------------------ %%
[cpName1, cpVal1] = local_mapInput(spec1, value1, prop, fluid);
[cpName2, cpVal2] = local_mapInput(spec2, value2, prop, fluid);

if strcmp(cpName1, cpName2)
    error('refpropm:degenerateInputPair', ...
        'Both input specifiers resolved to ''%s'' (''%s''/''%s''). Cannot fix a state.', ...
        cpName1, spec1, spec2);
end

%% ------------------------------------------------------------------ %%
%% Evaluate each requested property
%% ------------------------------------------------------------------ %%
for i = 1:max(nargout,1)
    code = prop(i);

    if CACHE_ENABLED
        key = sprintf('%s|%s|%.17g|%s|%.17g|%s', code, cpName1, cpVal1, cpName2, cpVal2, fluid);
        if isKey(cacheMap, key)
            varargout{i} = cacheMap(key);
            continue
        end
    end

    val = local_evaluate(code, cpName1, cpVal1, cpName2, cpVal2, fluid, ...
                         spec1, value1, spec2, value2);

    if CACHE_ENABLED
        cacheMap(key) = val; %#ok<NASGU>
    end
    varargout{i} = val;
end

end % local_core


%% ==================================================================== %%
%% Property evaluation
%% ==================================================================== %%
function val = local_evaluate(code, n1, v1, n2, v2, fluid, s1, r1, s2, r2)

switch code
    % --- direct CoolProp outputs, SI units identical to refpropm --------
    case 'b',  val = local_props('isobaric_expansion_coefficient', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'c',  val = local_props('Cpmass',       n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'd',  val = local_props('Dmass',        n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'h',  val = local_props('Hmass',        n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'l',  val = local_props('conductivity', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'o',  val = local_props('Cvmass',       n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 's',  val = local_props('Smass',        n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 't',  val = local_props('T',            n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'u',  val = local_props('Umass',        n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'v',  val = local_props('viscosity',    n1,v1,n2,v2, fluid, code,s1,r1,s2,r2); % Pa*s, no conversion
    case '^',  val = local_props('Prandtl',      n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'a',  val = local_props('speed_of_sound',n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
    case 'k',  val = local_props('Cpmass',n1,v1,n2,v2,fluid,code,s1,r1,s2,r2) / ...
                     local_props('Cvmass',n1,v1,n2,v2,fluid,code,s1,r1,s2,r2);
    case 'z',  val = local_props('Z',            n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);

    % --- unit conversions ----------------------------------------------
    case 'p'   % CoolProp Pa -> refpropm kPa
        val = local_props('P', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2) / 1000;

    case 'm'   % CoolProp kg/mol -> refpropm g/mol
        val = local_props('M', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2) * 1000;

    % --- quality, with REFPROP out-of-dome flags -----------------------
    case 'q'
        val = local_quality(n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);

    % --- heat of vaporisation ------------------------------------------
    case 'y'
        % NIST refpropm case 'y' does a saturation flash at T only
        % (SATTdll at T, then h(Dv)-h(Dl)); the second input is ignored.
        if strcmp(n1,'T')
            Tsat = v1;
        elseif strcmp(n2,'T')
            Tsat = v2;
        else
            Tsat = local_props('T', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
        end
        hv = local_props('Hmass','T',Tsat,'Q',1, fluid, code,s1,r1,s2,r2);
        hl = local_props('Hmass','T',Tsat,'Q',0, fluid, code,s1,r1,s2,r2);
        val = hv - hl;

    otherwise
        error('refpropm:unsupportedProperty', ...
            ['Property code ''%s'' is not implemented in this CoolProp shim.\n' ...
             'Implemented: B C D H L O P Q/q S T U V Y ^ A K M Z\n' ...
             'Refusing to guess -- add it explicitly after checking ' ...
             'refpropm.m and the call site.'], code);
end

if ~isnumeric(val) || ~isscalar(val) || ~isfinite(val)
    error('refpropm:nonFiniteResult', ...
        ['Property ''%s'' returned a non-finite value for %s at ' ...
         '%s=%.10g, %s=%.10g.'], code, fluid, s1, r1, s2, r2);
end
end


%% ==================================================================== %%
%% Quality with REFPROP-style out-of-dome flags
%% ==================================================================== %%
function q = local_quality(n1,v1,n2,v2, fluid, code,s1,r1,s2,r2)
q = local_props('Q', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);

if q >= 0 && q <= 1
    return   % genuinely two-phase; pure fluid so mass == mole basis
end

% Out of the dome: CoolProp returns a sentinel (-1 or 1e4 depending on
% version and input pair). Translate to REFPROP's convention so the value
% is readable and portable, using an explicit phase query.
phase = local_props('Phase', n1,v1,n2,v2, fluid, code,s1,r1,s2,r2);
switch phase
    case 0                   % iphase_liquid
        q = -998;
    case 5                   % iphase_gas
        q = 998;
    case {1, 2, 3, 4}        % supercritical / supercritical_gas / _liquid / critical
        q = 999;
    case 6                   % iphase_twophase (shouldn't reach here)
        error('refpropm:qualityInconsistent', ...
            'CoolProp reports two-phase but returned quality %.6g for %s.', q, fluid);
    otherwise
        error('refpropm:unknownPhase', ...
            'CoolProp returned unknown phase index %g for %s at %s=%.10g, %s=%.10g.', ...
            phase, fluid, s1, r1, s2, r2);
end
end


%% ==================================================================== %%
%% Fixed-point (critical / triple / max) queries
%% ==================================================================== %%
function val = local_fixedPoint(code, spec1, fluid)
switch spec1
    case 'c'
        switch code
            case 't', val = local_trivial('Tcrit',   fluid);
            case 'p', val = local_trivial('Pcrit',   fluid) / 1000;   % kPa
            case 'd', val = local_trivial('rhomass_critical', fluid);
            otherwise
                error('refpropm:unsupportedFixedPoint', ...
                    'Critical-point query supports T, P, D only; got ''%s''.', code);
        end
    case 'r'
        switch code
            case 't', val = local_trivial('Ttriple', fluid);
            case 'p', val = local_trivial('ptriple', fluid) / 1000;   % kPa
            case 'd'
                Tt  = local_trivial('Ttriple', fluid);
                val = local_props('Dmass','T',Tt,'Q',0, fluid, code,'t',Tt,'q',0);
            otherwise
                error('refpropm:unsupportedFixedPoint', ...
                    'Triple-point query supports T, P, D only; got ''%s''.', code);
        end
    case 'm'
        switch code
            case 't', val = local_trivial('Tmax', fluid);
            case 'p', val = local_trivial('pmax', fluid) / 1000;      % kPa
            otherwise
                error('refpropm:unsupportedFixedPoint', ...
                    'Max-condition query supports T, P only; got ''%s''.', code);
        end
end
end


%% ==================================================================== %%
%% Input specifier mapping
%% ==================================================================== %%
function [name, val] = local_mapInput(spec, value, prop, fluid)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    error('refpropm:badInputValue', ...
        'Input ''%s'' for property ''%s'' (%s) is not a finite scalar.', ...
        spec, prop, fluid);
end
switch spec
    case 't', name = 'T';      val = value;
    case 'p', name = 'P';      val = value * 1000;   % kPa -> Pa
    case 'd', name = 'Dmass';  val = value;
    case 'h', name = 'Hmass';  val = value;
    case 's', name = 'Smass';  val = value;
    case 'u', name = 'Umass';  val = value;
    case 'q', name = 'Q';      val = value;
    otherwise
        error('refpropm:unsupportedInputSpec', ...
            ['Input specifier ''%s'' is not implemented in this CoolProp shim.\n' ...
             'Implemented: T P D H S U Q (plus C/R/M as spec1).'], spec);
end
end


%% ==================================================================== %%
%% Fluid name mapping
%% ==================================================================== %%
function name = local_mapFluid(raw)
%LOCAL_MAPFLUID  Map a refpropm fluid string to a CoolProp fluid name.
%
%   Supports an OPTIONAL phase hint appended with '|':
%       'PARAHYD'          normal behaviour
%       'PARAHYD|liquid'   force the liquid root for T,P inputs
%       'PARAHYD|gas'      force the vapour root for T,P inputs
%
%   The hint exists because (T,P) does not identify a unique state on the
%   saturation line, and a caller that is tracking a specific phase (for
%   example the bulk liquid being pumped out of a tank) needs the root
%   belonging to THAT phase, not whichever root the flash happens to pick.
%   Without it, a pressure that drifts a fraction of a pascal below Psat
%   silently returns the vapour root - a ~70x jump in entropy - which
%   makes the ODE right-hand side discontinuous.
%
%   The hint is a deliberate extension beyond NIST refpropm. It is inert
%   unless used, so every existing call site behaves exactly as before.
%   See SATURATION_FAILURE_ANALYSIS.md.

if isstring(raw), raw = char(raw); end
if ~ischar(raw)
    error('refpropm:badFluid', 'Fluid name must be a character vector.');
end

hint = '';
bar  = strfind(raw, '|');
if ~isempty(bar)
    hint = lower(strtrim(raw(bar(1)+1:end)));
    raw  = raw(1:bar(1)-1);
    if ~any(strcmp(hint, {'liquid','gas','vapour','vapor'}))
        error('refpropm:badPhaseHint', ...
            ['Phase hint ''%s'' not recognised. Use ''|liquid'' or ''|gas''.'], hint);
    end
    if any(strcmp(hint, {'vapour','vapor'})), hint = 'gas'; end
end

key = lower(strtrim(raw));
key = regexprep(key, '\.(fld|ppf)$', '');   % tolerate 'parahyd.fld'

switch key
    case {'parahyd','parahydrogen','para-hydrogen','p-h2'}
        name = 'ParaHydrogen';
    case {'hydrogen','normalhydrogen','normal hydrogen','h2','n-h2'}
        % NOTE: LH2Simulate_Pump.m line 666 calls this fluid with an
        % entropy taken from PARAHYD. That fluid mixing is upstream
        % behaviour and is reproduced faithfully here. See SHIM_NOTES.md.
        name = 'Hydrogen';
    case {'orthohyd','orthohydrogen','ortho-hydrogen','o-h2'}
        name = 'OrthoHydrogen';
    otherwise
        error('refpropm:unknownFluid', ...
            ['Fluid ''%s'' is not mapped in this shim. Add it explicitly ' ...
             'rather than passing the raw string to CoolProp, so that a ' ...
             'typo cannot silently select the wrong fluid.'], raw);
end

if ~isempty(hint)
    name = [name '|' hint];      % carried through; stripped at point of use
end
end


%% ==================================================================== %%
%% Split a possibly hinted fluid name into base name and phase hint
%% ==================================================================== %%
function [base, hint] = local_splitFluid(fluid)
bar = strfind(fluid, '|');
if isempty(bar)
    base = fluid; hint = '';
else
    base = fluid(1:bar(1)-1);
    hint = fluid(bar(1)+1:end);
end
end


%% ==================================================================== %%
%% CoolProp bridge
%% ==================================================================== %%
function val = local_props(out, n1, v1, n2, v2, fluid, code, s1, r1, s2, r2)

[base, hint] = local_splitFluid(fluid);
isTP = (strcmp(n1,'T') && strcmp(n2,'P')) || (strcmp(n1,'P') && strcmp(n2,'T'));

% A phase hint on a T,P call means the caller is tracking a specific phase
% and wants THAT root, continuously, including where it is metastable.
% This is the only way to get a smooth property through the saturation
% pressure; the unhinted flash necessarily jumps between roots there.
if ~isempty(hint) && isTP
    if strcmp(n1,'T'), Tk = v1; Pa = v2; else, Tk = v2; Pa = v1; end
    try
        val = local_imposedPhaseTP(out, Tk, Pa, base, hint);
        return
    catch ME2
        error('refpropm:imposedPhaseFailed', ...
            ['Imposed-phase (%s) evaluation of ''%s'' failed for %s at ' ...
             'T = %.10g K, P = %.10g Pa.\n  %s'], ...
            hint, out, base, Tk, Pa, ME2.message);
    end
end
fluid = base;

try
    val = double(py.CoolProp.CoolProp.PropsSI(out, n1, v1, n2, v2, fluid));
    return
catch ME
    % ---------------------------------------------------------------
    % Saturation-boundary rescue for (T,P) inputs.
    %
    % CoolProp refuses a T,P request when P is within 1e-4 % of Psat(T),
    % because on the saturation line T and P are not independent and the
    % pair does not identify a unique state. REFPROP resolves a root
    % instead of refusing. Rather than let the caller's try/catch
    % substitute a different formula (which makes the ODE right-hand
    % side discontinuous and stalls the solver), resolve the phase
    % explicitly here and evaluate with that phase imposed. The result
    % is continuous through the saturation pressure.
    %
    % See SATURATION_FAILURE_ANALYSIS.md. Only triggers for T,P inputs
    % on that specific CoolProp error; every other failure still raises.
    % ---------------------------------------------------------------
    isTP = (strcmp(n1,'T') && strcmp(n2,'P')) || (strcmp(n1,'P') && strcmp(n2,'T'));
    if isTP && contains(ME.message, 'Saturation pressure') ...
            && contains(ME.message, 'within')
        if strcmp(n1,'T'), Tk = v1; Pa = v2; else, Tk = v2; Pa = v1; end
        try
            val = local_imposedPhaseTP(out, Tk, Pa, fluid, '');
            return
        catch ME2
            error('refpropm:saturationRescueFailed', ...
                ['CoolProp refused ''%s'' (refpropm code ''%s'') at the saturation\n' ...
                 'boundary for %s, and the imposed-phase rescue also failed.\n' ...
                 '  T = %.10g K , P = %.10g Pa\n  original : %s\n  rescue   : %s'], ...
                out, code, fluid, Tk, Pa, ME.message, ME2.message);
        end
    end

    error('refpropm:coolpropFailed', ...
        ['CoolProp failed evaluating ''%s'' (refpropm code ''%s'') for %s.\n' ...
         '  requested state : %s = %.10g , %s = %.10g   [refpropm units]\n' ...
         '  passed to CoolProp: %s = %.10g , %s = %.10g   [SI]\n' ...
         '  CoolProp said   : %s'], ...
        out, code, fluid, s1, r1, s2, r2, n1, v1, n2, v2, ME.message);
end
end


%% ==================================================================== %%
%% Imposed-phase (T,P) evaluation
%% ==================================================================== %%
function val = local_imposedPhaseTP(out, Tk, Pa, fluid, hint)
%LOCAL_IMPOSEDPHASETP  Evaluate a T,P state with the phase chosen explicitly.
%
%   hint = 'liquid' or 'gas'  -> that root is used unconditionally, giving
%                                a property that is CONTINUOUS through the
%                                saturation pressure (the root continues
%                                smoothly into its metastable extension).
%   hint = ''                 -> the phase is chosen by comparing P with
%                                Psat(T). This removes CoolProp's exception
%                                but NOT the physical jump between roots,
%                                because the two roots genuinely differ.
%
%   Verified for parahydrogen at T = 20.9095 K: with 'liquid' imposed, the
%   largest jump between adjacent samples spanning Psat is 1.3e-4 J/kg/K;
%   choosing by Psat instead leaves a 2.1e+4 J/kg/K jump.

persistent AS ASfluid

% CoolProp enum values (CoolProp.constants), pinned so this file stays
% self-contained and does not depend on the Python module layout:
PT_INPUTS     = int32(17);
IPHASE_LIQUID = int32(0);
IPHASE_GAS    = int32(5);

if strcmp(hint,'liquid')
    phaseIdx = IPHASE_LIQUID;
elseif strcmp(hint,'gas')
    phaseIdx = IPHASE_GAS;
else
    % No hint: decide from the saturation curve. Above Tcrit there is no
    % saturation state to compare against, so nothing can be rescued.
    Tcrit = double(py.CoolProp.CoolProp.PropsSI('Tcrit', fluid));
    if Tk >= Tcrit
        error('refpropm:noSaturationAboveTcrit', ...
            'T = %.10g K is at or above Tcrit = %.10g K; no saturation state exists.', ...
            Tk, Tcrit);
    end
    Psat = double(py.CoolProp.CoolProp.PropsSI('P', 'T', Tk, 'Q', 0, fluid));
    if Pa >= Psat
        phaseIdx = IPHASE_LIQUID;
    else
        phaseIdx = IPHASE_GAS;
    end
end

if isempty(AS) || ~strcmp(ASfluid, fluid)
    AS = py.CoolProp.CoolProp.AbstractState('HEOS', fluid);
    ASfluid = fluid;
end

AS.specify_phase(phaseIdx);
AS.update(PT_INPUTS, Pa, Tk);

switch out
    case 'Dmass',        val = double(AS.rhomass());
    case 'Hmass',        val = double(AS.hmass());
    case 'Smass',        val = double(AS.smass());
    case 'Umass',        val = double(AS.umass());
    case 'Cpmass',       val = double(AS.cpmass());
    case 'Cvmass',       val = double(AS.cvmass());
    case 'conductivity', val = double(AS.conductivity());
    case 'viscosity',    val = double(AS.viscosity());
    case 'Prandtl',      val = double(AS.Prandtl());
    case 'speed_of_sound', val = double(AS.speed_sound());
    case 'isobaric_expansion_coefficient'
                         val = double(AS.isobaric_expansion_coefficient());
    case 'T',            val = Tk;
    case 'P',            val = Pa;
    otherwise
        error('refpropm:imposedPhaseUnsupported', ...
            ['Output ''%s'' is not available through the imposed-phase path.\n' ...
             'Add it explicitly rather than guessing an AbstractState method.'], out);
end
end

function val = local_trivial(out, fluid)
fluid = local_splitFluid(fluid);   % a phase hint is meaningless here
try
    val = double(py.CoolProp.CoolProp.PropsSI(out, fluid));
catch ME
    error('refpropm:coolpropFailed', ...
        'CoolProp failed evaluating trivial property ''%s'' for %s: %s', ...
        out, fluid, ME.message);
end
end


%% ==================================================================== %%
%% Memoisation
%% ==================================================================== %%
%  Set CACHE_ENABLED = true at the top of this file only AFTER
%  validate_shim.m passes and a baseline run has been recorded. The cache
%  is keyed on the full-precision (%.17g) SI inputs, so it is exact:
%  identical inputs return identical outputs. It never interpolates.
%
%  To clear it between runs:  clear refpropm
%
%  Expected benefit: the ODE right-hand side re-requests several
%  properties at the same state within one evaluation (e.g. L, V, O, C, B
%  are all called at the same T,Q=1). Those repeats become map lookups.
%  It will NOT help across solver steps, since the state changes.
