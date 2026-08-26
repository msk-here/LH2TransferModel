function varargout = refpropm(prop, spec1, value1, spec2, value2, varargin)
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

end % refpropm


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
if isstring(raw), raw = char(raw); end
if ~ischar(raw)
    error('refpropm:badFluid', 'Fluid name must be a character vector.');
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
end


%% ==================================================================== %%
%% CoolProp bridge
%% ==================================================================== %%
function val = local_props(out, n1, v1, n2, v2, fluid, code, s1, r1, s2, r2)
try
    val = double(py.CoolProp.CoolProp.PropsSI(out, n1, v1, n2, v2, fluid));
catch ME
    error('refpropm:coolpropFailed', ...
        ['CoolProp failed evaluating ''%s'' (refpropm code ''%s'') for %s.\n' ...
         '  requested state : %s = %.10g , %s = %.10g   [refpropm units]\n' ...
         '  passed to CoolProp: %s = %.10g , %s = %.10g   [SI]\n' ...
         '  CoolProp said   : %s'], ...
        out, code, fluid, s1, r1, s2, r2, n1, v1, n2, v2, ME.message);
end
end

function val = local_trivial(out, fluid)
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
