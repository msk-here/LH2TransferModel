%% validate_shim.m
%  Pre-flight check for the CoolProp refpropm shim.
%  Run this BEFORE MAIN.m. If it does not print ALL CHECKS PASSED, do not
%  run the model -- a mis-mapped property code produces figures that look
%  entirely plausible and are wrong.
%
%  Every check below is chosen to fail loudly for one specific mistake.
%  The identity checks (section 3) are the important ones: they do not
%  depend on any reference table, only on thermodynamics, so they catch a
%  swapped or mis-scaled code even if CoolProp itself changes version.
%
%  Usage:  >> validate_shim

clear refpropm; clc;
R = struct('name',{},'pass',{},'detail',{});

fprintf('=====================================================\n');
fprintf(' refpropm -> CoolProp shim validation\n');
fprintf('=====================================================\n\n');

PARA = 'PARAHYD';

%% ------------------------------------------------------------------ %%
fprintf('[0] Environment\n');
%% ------------------------------------------------------------------ %%
% MATLAB loads Python LAZILY: pyenv reports Status="NotLoaded" until the
% first py.* call of the session. Querying pyenv before touching Python
% therefore always reports NotLoaded, which is not a fault. Force the
% interpreter up first, THEN re-query.
try
    pyver  = char(py.sys.version);      % this is what actually loads Python
    loadOK = true;
catch ME
    pyver  = ME.message;
    loadOK = false;
end
pe = pyenv;                              % snapshot AFTER the load
R = tRue(R, 'python bridge loaded', loadOK && pe.Status == "Loaded", ...
    sprintf('Status=%s, Mode=%s, Python=%s', pe.Status, pe.ExecutionMode, strtok(pyver)));

if pe.ExecutionMode ~= "InProcess"
    fprintf(['    WARNING: ExecutionMode is %s. Every property call crosses a\n' ...
             '             process boundary; the ODE right-hand side makes ~85 of\n' ...
             '             them per evaluation. Use pyenv(ExecutionMode="InProcess").\n'], ...
             pe.ExecutionMode);
end

R = tRue(R, 'CoolProp importable', ...
    ~isempty(py.importlib.util.find_spec('CoolProp')), 'py -m pip install CoolProp');
try
    cpver = char(py.CoolProp.CoolProp.get_global_param_string('version'));
catch, cpver = '<unavailable>';
end
fprintf('    CoolProp version: %s\n', cpver);

%% ------------------------------------------------------------------ %%
fprintf('\n[1] Fluid constants queried at runtime (never hardcode these)\n');
%% ------------------------------------------------------------------ %%
Tcrit   = refpropm('T','C',0,' ',0,PARA);
Pcrit   = refpropm('P','C',0,' ',0,PARA);     % kPa
Dcrit   = refpropm('D','C',0,' ',0,PARA);
Ttriple = refpropm('T','R',0,' ',0,PARA);

R = tEq(R,'Tcrit  [K]',    Tcrit,   32.93785506891549, 1e-9, '');
R = tEq(R,'Pcrit  [kPa]',  Pcrit,   1285.7761785274085,1e-9, 'refpropm returns kPa');
R = tEq(R,'rhocrit[kg/m3]',Dcrit,   31.31543601362373, 1e-9, '');
R = tEq(R,'Ttriple[K]',    Ttriple, 13.8033,           1e-6, '');

% The trap: the repo hardcodes LH2Model.T_c = 32.938, which is ABOVE Tcrit.
R = tRue(R,'hardcoded 32.938 is above Tcrit (documents the trap)', ...
    32.938 > Tcrit, sprintf('32.938 exceeds Tcrit by %.3e K -> any Q-flash at T_c throws', 32.938-Tcrit));

%% ------------------------------------------------------------------ %%
fprintf('\n[2] Unit traps (refpropm conventions, NOT CoolProp SI)\n');
%% ------------------------------------------------------------------ %%
Tnbp = refpropm('T','P',101.325,'Q',0,PARA);      % P input in kPa
R = tEq(R,'NBP from P=101.325 kPa [K]', Tnbp, 20.271251, 1e-5, ...
    'validates T output + P INPUT in kPa + Q input together');

Psat = refpropm('P','T',Tnbp,'Q',0,PARA);
R = tEq(R,'P OUTPUT in kPa', Psat, 101.325, 1e-5, ...
    'if this reads ~101325 the Pa->kPa conversion is missing');

muL = refpropm('V','T',Tnbp,'Q',0,PARA);
R = tEq(R,'V OUTPUT in Pa*s', muL, 1.349616e-05, 5e-3, ...
    'if this reads ~13.5 the shim wrongly applied a 1e6 factor');
R = tRue(R,'V magnitude sane for LH2', muL < 1e-3, ...
    sprintf('mu_L = %.6e Pa*s; Parameters_*.m hardcodes 13.54e-6 [Pa*s]', muL));

Mw = refpropm('M','T',Tnbp,'Q',0,PARA);
R = tEq(R,'M OUTPUT in g/mol', Mw, 2.01588, 1e-4, 'CoolProp gives kg/mol');

%% ------------------------------------------------------------------ %%
fprintf('\n[3] Property-code identities (catch a swapped or mis-scaled code)\n');
%% ------------------------------------------------------------------ %%
% 3a. Prandtl == mu*cp/k.  Validates ^, V, C, L simultaneously, and is the
%     single strongest check on the viscosity unit convention.
for T = [21.0, 25.0, 28.0]
    Pr = refpropm('^','T',T,'Q',1,PARA);
    mu = refpropm('V','T',T,'Q',1,PARA);
    cp = refpropm('C','T',T,'Q',1,PARA);
    k  = refpropm('L','T',T,'Q',1,PARA);
    R = tEq(R, sprintf('^ == V*C/L at T=%.0fK (sat vap)',T), Pr, mu*cp/k, 1e-9, ...
        'fails by 1e6 if V is returned in uPa*s');
end

% 3b. U == H - P/rho.  Validates U, H, P, D and the kPa->Pa conversion.
Tv = 28.226; pv_kPa = 600;
h = refpropm('H','T',Tv,'P',pv_kPa,PARA);
d = refpropm('D','T',Tv,'P',pv_kPa,PARA);
u = refpropm('U','T',Tv,'P',pv_kPa,PARA);
R = tEq(R,'U == H - P/rho (P in kPa -> *1000)', u, h - (pv_kPa*1000)/d, 1e-8, ...
    'off by 1000x if the pressure unit is wrong');

% 3c. Clausius: hvap == Tsat*(s_vap - s_liq).  Validates Y and S together.
for T = [21.0, 25.0, 28.0]
    Y  = refpropm('Y','T',T,'Q',0,PARA);
    sv = refpropm('S','T',T,'Q',1,PARA);
    sl = refpropm('S','T',T,'Q',0,PARA);
    R = tEq(R, sprintf('Y == T*(Sv-Sl) at T=%.0fK',T), Y, T*(sv-sl), 1e-9, ...
        'validates heat of vaporisation AND entropy');
end

% 3d. Y also equals the enthalpy difference across the dome.
Y21 = refpropm('Y','T',21,'Q',0,PARA);
R = tEq(R,'Y == H(Q=1) - H(Q=0)', Y21, ...
    refpropm('H','T',21,'Q',1,PARA) - refpropm('H','T',21,'Q',0,PARA), 1e-9, '');
R = tEq(R,'Y at NBP [J/kg]', refpropm('Y','T',Tnbp,'Q',0,PARA), 446066.07, 1e-4, ...
    'literature latent heat of para-H2 ~446 kJ/kg');

% 3e. C is cp and O is cv, not the other way round.
cp = refpropm('C','T',25,'Q',1,PARA);
cv = refpropm('O','T',25,'Q',1,PARA);
R = tRue(R,'C (cp) > O (cv)', cp > cv, sprintf('cp=%.1f cv=%.1f', cp, cv));
gam = refpropm('C','T',40,'P',1,PARA) / refpropm('O','T',40,'P',1,PARA);
R = tEq(R,'C/O -> 5/3 in dilute limit', gam, 5/3, 5e-3, ...
    'para-H2 has frozen rotation at low T; Parameters_*.m sets gamma_=5/3');

% 3f. B is volumetric expansivity [1/K]: beta -> 1/T for a dilute gas.
b80 = refpropm('B','T',80,'P',10,PARA);
R = tEq(R,'B -> 1/T in dilute limit', b80*80, 1.0, 5e-3, ...
    'if B were cp or cv this is off by many orders of magnitude');
bL = refpropm('B','T',21,'Q',0,PARA);
R = tRue(R,'B for sat liquid is small and positive', bL > 0 && bL < 1, ...
    sprintf('beta_L(21K) = %.6f 1/K (feeds the Rayleigh numbers)', bL));

% 3g. Round-trip consistency across input pairs.
rho = refpropm('D','T',Tv,'P',pv_kPa,PARA);
uu  = refpropm('U','T',Tv,'D',rho,PARA);
R = tEq(R,'T round-trip via (D,U)', refpropm('T','D',rho,'U',uu,PARA), Tv, 1e-7, '');
R = tEq(R,'P round-trip via (D,U)', refpropm('P','D',rho,'U',uu,PARA), pv_kPa, 1e-7, '');
R = tEq(R,'D round-trip via (P,U)', refpropm('D','P',pv_kPa,'U',uu,PARA), rho, 1e-7, '');

%% ------------------------------------------------------------------ %%
fprintf('\n[4] Quality: branching must match the model''s (q>0 && q<1) test\n');
%% ------------------------------------------------------------------ %%
% Two-phase
d2 = refpropm('D','T',25,'Q',0.5,PARA);
u2 = refpropm('U','T',25,'Q',0.5,PARA);
q2 = refpropm('q','D',d2,'U',u2,PARA);
R = tEq(R,'two-phase q recovered', q2, 0.5, 1e-6, '');
R = tRue(R,'two-phase takes the SATURATED branch', q2 > 0 && q2 < 1, ...
    sprintf('q = %.6f', q2));

% Superheated vapour
qv = refpropm('q','D',rho,'U',uu,PARA);
R = tRue(R,'superheated vapour takes the D,U branch', ~(qv > 0 && qv < 1), ...
    sprintf('q flag = %g (REFPROP uses 998)', qv));

% Subcooled liquid
dl = refpropm('D','T',21,'P',600,PARA);
ul = refpropm('U','T',21,'P',600,PARA);
ql = refpropm('q','D',dl,'U',ul,PARA);
R = tRue(R,'subcooled liquid takes the D,U branch', ~(ql > 0 && ql < 1), ...
    sprintf('q flag = %g (REFPROP uses -998)', ql));

% refpropm lowercases the request, so 'q' and 'Q' must agree.
R = tEq(R,'''q'' and ''Q'' are the same code', ...
    refpropm('Q','D',rho,'U',uu,PARA), qv, 0, ...
    'NIST refpropm.m line 328: propReq = lower(varargin{1})');

%% ------------------------------------------------------------------ %%
fprintf('\n[5] Every call shape that appears in the repository\n');
%% ------------------------------------------------------------------ %%
% (output, spec1, val1, spec2, val2, fluid) -- realistic model states.
S = { ...
 'B','T',21,'Q',0,PARA;      'B','D',rho,'U',uu,PARA; ...
 'C','T',21,'Q',1,PARA;      'C','D',rho,'U',uu,PARA; ...
 'D','T',Tv,'P',600,PARA;    'D','T',21,'Q',0,PARA;    'D','P',600,'U',uu,PARA; ...
 'H','T',21,'Q',0,PARA;      'H','T',21,'D',dl,PARA;   'H','T',21,'P',600,PARA; ...
 'L','T',21,'Q',1,PARA;      'L','D',rho,'U',uu,PARA; ...
 'O','T',21,'Q',1,PARA;      'O','D',rho,'U',uu,PARA; ...
 'P','T',21,'Q',0,PARA;      'P','D',rho,'U',uu,PARA; ...
 'Q','D',rho,'U',uu,PARA;    'q','D',rho,'U',uu,PARA; ...
 'S','T',21,'P',600,PARA;    'S','T',21,'Q',0,PARA; ...
 'T','D',rho,'U',uu,PARA;    'T','P',600,'U',uu,PARA; 'T','P',600,'Q',0,PARA; ...
 'T','P',600,'H',h,PARA; ...
 'U','T',21,'Q',0,PARA;      'U','T',21,'D',dl,PARA; ...
 'V','T',21,'Q',1,PARA;      'V','D',rho,'U',uu,PARA; ...
 'Y','T',21,'Q',0,PARA; ...
 '^','T',21,'Q',1,PARA;      '^','D',rho,'U',uu,PARA; ...
 };
nbad = 0;
for i = 1:size(S,1)
    try
        v = refpropm(S{i,1},S{i,2},S{i,3},S{i,4},S{i,5},S{i,6});
        if ~isfinite(v), error('non-finite'); end
    catch ME
        nbad = nbad + 1;
        fprintf('    !! %s(%s,%s) -> %s\n', S{i,1},S{i,2},S{i,4}, ME.message);
    end
end
R = tRue(R, sprintf('all %d repo call shapes evaluate', size(S,1)), nbad==0, ...
    sprintf('%d failed', nbad));

% The one non-PARAHYD call in the repo: LH2Simulate_Pump.m line 666.
try
    sL = refpropm('S','T',21,'P',600,PARA);
    hh = refpropm('H','P',300,'S',sL,'hydrogen');
    R = tRue(R,'''hydrogen'' fluid string resolves (Pump line 666)', isfinite(hh), ...
        sprintf('h_isen = %.2f J/kg -- NOTE: entropy came from PARAHYD, see SHIM_NOTES.md', hh));
catch ME
    R = tRue(R,'''hydrogen'' fluid string resolves', false, ME.message);
end

%% ------------------------------------------------------------------ %%
fprintf('\n[6] Loud failure (no silent fallbacks)\n');
%% ------------------------------------------------------------------ %%
R = tRue(R,'unsupported property code throws', ...
    throwsFor(@() refpropm('W','T',21,'Q',0,PARA)), 'must not return a default');
R = tRue(R,'unsupported input spec throws', ...
    throwsFor(@() refpropm('D','A',21,'Q',0,PARA)), '');
R = tRue(R,'unknown fluid throws', ...
    throwsFor(@() refpropm('D','T',21,'Q',0,'PARAHYDROGEN_TYPO')), '');
R = tRue(R,'impossible state throws', ...
    throwsFor(@() refpropm('D','T',Tcrit+50,'Q',0,PARA)), 'Q-flash above Tcrit');

%% ------------------------------------------------------------------ %%
fprintf('\n[7] Scenario B initialisation: is the ullage vapour or liquid?\n');
%% ------------------------------------------------------------------ %%
psiToPa = 6894.75729;
Tv0 = @(p) 0.1+(-1.603941638811E-11*(p/psiToPa)^6 + 7.830478134841E-09*(p/psiToPa)^5 ...
    -1.549372675881E-06*(p/psiToPa)^4 + 1.614567978153E-04*(p/psiToPa)^3 ...
    -9.861776990784E-03*(p/psiToPa)^2 + 4.314905904166E-01*(p/psiToPa) + 1.559843335080E+01);
for pbar = [3 5 6]
    p = pbar*1e5;
    Tsat = refpropm('T','P',p/1000,'Q',0,PARA);
    T0   = Tv0(p);
    rv   = refpropm('D','T',T0,'P',p/1000,PARA);
    R = tRue(R, sprintf('ullage at %d bar initialises SUPERHEATED', pbar), ...
        T0 > Tsat && rv < 20, ...
        sprintf('Tsat=%.3f K, code uses Tv0=%.3f K (+%.3f K), rho_v=%.3f kg/m3', ...
                Tsat, T0, T0-Tsat, rv));
end
% What the paper's stated 25 K would have done, for the record.
rho25 = refpropm('D','T',25,'P',600,PARA);
fprintf('    NOTE: the paper''s stated 25 K at 6 bar would give rho = %.1f kg/m3 (LIQUID).\n', rho25);
fprintf('          The parameter file does NOT use 25 K, so that trap does not fire here.\n');

%% ------------------------------------------------------------------ %%
%% Summary
%% ------------------------------------------------------------------ %%
np = sum([R.pass]); nt = numel(R);
fprintf('\n=====================================================\n');
if np == nt
    fprintf(' ALL CHECKS PASSED  (%d/%d)  -- safe to run MAIN.m\n', np, nt);
else
    fprintf(' %d of %d CHECKS FAILED -- DO NOT RUN THE MODEL\n', nt-np, nt);
    for i = 1:nt
        if ~R(i).pass, fprintf('   FAILED: %s   [%s]\n', R(i).name, R(i).detail); end
    end
end
fprintf('=====================================================\n');


%% ==================== helpers ==================== %%
function R = tEq(R, name, actual, expected, reltol, why)
if expected == 0
    ok = abs(actual) <= reltol;
    err = abs(actual);
else
    err = abs(actual-expected)/abs(expected);
    ok = err <= reltol;
end
R(end+1) = struct('name',name,'pass',ok, ...
    'detail',sprintf('got %.10g expected %.10g relerr %.2e', actual, expected, err));
fprintf('    [%s] %-42s %14.8g   %s\n', tick(ok), name, actual, why);
end

function R = tRue(R, name, cond, detail)
cond = logical(cond);
R(end+1) = struct('name',name,'pass',cond,'detail',detail);
fprintf('    [%s] %-42s %s\n', tick(cond), name, detail);
end

function s = tick(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function tf = throwsFor(fh)
try
    fh(); tf = false;
catch
    tf = true;
end
end
