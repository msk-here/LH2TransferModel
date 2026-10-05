%TEST_TOPFILL_SOURCES Revision 3 module acceptance, MATLAB R2021a+.
% cd to this folder and run: test_topfill_sources
% The supplied refpropm.m must be here, on the path, in the parent repo,
% or in ../upload. The script finds it automatically; no script edits.
% Each test prints PASS/FAIL and numbers; the final line summarizes all tests.
% MATLAB execution is performed by the user; no toolbox beyond base MATLAB.
% Existing repo files are not edited. Reference-shift wrappers are temporary.

topfill_test_results = run_suite(fileparts(mfilename('fullpath')));
if all([topfill_test_results.passed])
    topfill_test_status = 'PASS';
else
    topfill_test_status = 'FAIL';
end
fprintf('SUMMARY: %s | PASS=%d FAIL=%d TOTAL=%d\n', topfill_test_status, ...
    nnz([topfill_test_results.passed]), nnz(~[topfill_test_results.passed]), numel(topfill_test_results));

function results = run_suite(folder)
old_path = path;
cleanup = onCleanup(@() path(old_path));
addpath(folder);
results = struct('name', {}, 'passed', {}, 'numbers', {});
try
    if isempty(which('refpropm'))
        candidates = {folder, fileparts(folder), fullfile(fileparts(folder), 'upload')};
        for k = 1:numel(candidates)
            if isfile(fullfile(candidates{k}, 'refpropm.m'))
                addpath(candidates{k}, '-begin');
                break;
            end
        end
    end
    assert(~isempty(which('refpropm')), 'Could not find the supplied refpropm.m.');
    pcrit = 1000*refpropm('P', 'C', 0, ' ', 0, 'PARAHYD');
    assert(isreal(pcrit) && isfinite(pcrit) && pcrit > 12e5, 'Invalid EOS critical pressure.');
    results(end+1) = report('property preflight', true, sprintf('p_crit=%.9g Pa', pcrit));
catch cause
    results(end+1) = report('property preflight', false, failure_text(cause));
    return;
end
P = Parameters_topfill_defaults(struct('g', 9.81, 'VTotal2', 1.7, 'A2', 1, 'VL20', 0.17));
defs = struct('name', {}, 'run', {});
defs(end+1) = entry('defaults and override preservation', @() check_defaults(P));
for mode = {'spray', 'jet'}
    m = mode{1};
    defs(end+1) = entry([m ' exact nonpositive-flow zeros'], @() check_zeros(m));
    for kind = {'subcooled', 'partial flash', 'all vapor', 'condensation', 'evaporation', 'dryout', 'cold vapor'}
        k = kind{1};
        defs(end+1) = entry([m ' ' k], @() check_physical_case(m, k, P));
    end
    defs(end+1) = entry([m ' zero/tiny height with flash'], @() check_zero_height(m, P));
    defs(end+1) = entry([m ' dryout transition'], @() check_dryout_transition(m, P));
    defs(end+1) = entry([m ' flow/height and flash sweeps'], @() check_sweeps(m, P));
    defs(end+1) = entry([m ' full/short-time conduction'], @() check_conduction(m, P));
    defs(end+1) = entry([m ' series-warning and legacy isolation'], @() check_warnings_and_legacy(m, P));
    defs(end+1) = entry([m ' reference-shift invariance'], @() check_reference_shifts(m, P));
    for icase = 1:6
        c = icase;
        defs(end+1) = entry(sprintf('case %d %s', c, m), @() check_case_family(c, m, P));
    end
end
D = [0.1, 1, 10]*1e-3;
targets = [1.05, 101, 0.229; 0.383, 5.29e3, 1.20; 0.489, 1.48e5, 3.36];
for k = 1:3
    d = D(k);
    t = targets(k, :);
    defs(end+1) = entry(sprintf('Fig. 12 D=%.3g mm', 1000*d), @() check_fig_point(d, t, P));
end
defs(end+1) = entry('Fig. 12 drag minimum', @() check_drag_minimum(P));
defs(end+1) = entry('Reynolds bases and diameter/Re warnings', @() check_reynolds(P));
defs(end+1) = entry('exact jet area, 1% warning and g=0', @() check_jet_area(P));
defs(end+1) = entry('host rate identities and split endpoints', @() check_host_rates(P));
defs(end+1) = entry('critical/invalid properties and no-root errors', @() check_errors(P));
for k = 1:numel(defs)
    try
        numbers = defs(k).run();
        results(end+1) = report(defs(k).name, true, numbers); %#ok<AGROW>
    catch cause
        results(end+1) = report(defs(k).name, false, failure_text(cause)); %#ok<AGROW>
    end
end
end

function d = entry(name, f)
d = struct('name', name, 'run', f);
end

function r = report(name, passed, numbers)
if passed, status = 'PASS'; else, status = 'FAIL'; end
fprintf('%s | %s | %s\n', status, name, numbers);
r = struct('name', name, 'passed', passed, 'numbers', numbers);
end

function text = failure_text(cause)
text = sprintf('%s: %s', cause.identifier, regexprep(cause.message, '\s+', ' '));
end

function text = check_defaults(P)
names = fieldnames(P);
for k = 1:numel(names)
    assert(~isempty(P.(names{k})), 'Empty default P.%s.', names{k});
end
assert(~P.TF_enabled && strcmp(P.TF_mode, 'spray') && P.TF_r == 0);
assert(P.TF_D_d == 0.006 && P.TF_D_0 == 0.02 && strcmp(P.TF_ReBasis, 'tenDamme'));
assert(P.TF_ell_g == (P.VTotal2-P.VL20)/P.A2 && P.TF_C_j == 1);
q = P;
q.TF_D_d = 0.001;
q.TF_seriesExponentLimit = 55;
q.ETinletdiameter = 0.04;
assert(isequaln(q, Parameters_topfill_defaults(q)), 'An existing field was overwritten.');
q = rmfield(P, 'TF_D_0');
q.ETinletdiameter = 0.03;
q = Parameters_topfill_defaults(q);
assert(q.TF_D_0 == 0.03);
assert(P.TF_heightTiny == 1e-9 && P.TF_seriesExponentLimit == 50 && P.TF_shortTimeFo == 1e-6);
assert(isequal(P.TF_velocityBracket, [1e-6, 50]) && P.TF_exactBesselRoots == 20);
assert(P.TF_J_scale == 1e-9 && P.TF_H_scale == 1e-3 && P.TF_jetAreaExcessLimit == 0.01);
text = sprintf('fields=%d empty=0 H_tiny=%.3g m exponent=%g exact_roots=%d', numel(names), P.TF_heightTiny, P.TF_seriesExponentLimit, P.TF_exactBesselRoots);
end

function text = check_zeros(mode)
maximum = 0;
for J = [0, -1]
    o = topfill_sources(mode, J, struct(), struct());
    v = ports(o);
    assert(isequal(v, zeros(1, 5)), 'J=%g: ports are not exact zero.', J); % Eq. (38), Section 4.4.
    finite_output(o);
    maximum = max(maximum, max(abs(v)));
end
text = sprintf('states=2 max_abs_port=%.17g', maximum);
end

function [s, J] = physical_state(kind)
p = 1000*refpropm('P', 'T', 21, 'Q', 0, 'PARAHYD'); % Eq. (15): 21 K reference.
s = state(p, 0, 0.5);
J = 0.1;
hg = refpropm('H', 'P', p/1000, 'Q', 1, 'PARAHYD'); % Eq. (15).
switch kind
    case {'subcooled', 'condensation'}
        s.h_in = refpropm('H', 'T', 19, 'P', p/1000, 'PARAHYD|liquid'); % Eq. (37): consistent subcooled inlet.
    case 'partial flash'
        s.h_in = s.h_in+0.4*(hg-s.h_in); % Eq. (37).
        s.T_v = s.T_v+1;
        s.rho_v = refpropm('D', 'T', s.T_v, 'P', p/1000, 'PARAHYD|gas');
        s.H_ullage = 0.01;
    case 'all vapor'
        s.h_in = hg+5e4; % Eq. (37): retain vapor superheat.
    case 'evaporation'
        s = state(p, 1, 0.01);
    case 'cold vapor'
        s = state(p, -0.5, 0.5); % Section 8: below-saturation gas continuation.
    case 'dryout'
        s = state(8.6e5, 0, 5);
        s.T_v = 80;
        s.rho_v = refpropm('D', 'T', 80, 'P', 860, 'PARAHYD|gas');
        J = 1e-4;
end
end

function text = check_physical_case(mode, kind, P)
[s, J] = physical_state(kind);
o = topfill_sources(mode, J, s, P);
r = balance(o, J, s, P);
switch kind
    case {'subcooled', 'condensation'}
        assert(o.x_flash == 0 && o.E < 0 && o.J_top_vap < 0 && o.J_top_liq > J, 'Condensation signs are wrong: E=%g Jv=%g.', o.E, o.J_top_vap); % Eq. (17).
        assert(o.Q_vap_to_top == 0 && o.h_bar > o.h_0 && o.K_v == 0); % Eqs. (18), (35), (46).
    case 'partial flash'
        assert(abs(o.x_flash-0.4) <= 1e-13 && o.F > 0 && o.M > 0); % Eq. (37).
        fast = s;
        fast.v_in = 40;
        f = topfill_sources(mode, J, fast, P);
        balance(f, J, fast, P);
        assert(f.x_flash == o.x_flash && f.E == o.E && f.Q_vap_to_top == o.Q_vap_to_top); % Eqs. (18), (37): kinetic allowance is separate.
    case 'all vapor'
        assert(o.x_flash == 1 && o.J_top_liq == 0 && o.H_top_liq == 0 && o.Q_vap_to_top == 0);
        assert(o.H_top_vap == J*(s.h_in+s.v_in^2/2)); % Eqs. (19), (37)-(38).
    case 'evaporation'
        assert(o.Q_vap_to_top > 0 && o.E > 0 && ~o.dryout && o.J_top_liq > 0); % Eqs. (17), (38).
    case 'dryout'
        assert(o.dryout && o.E == o.M && o.J_top_liq == 0 && o.H_top_liq == 0);
        assert(o.Q_raw >= o.Q_dry && o.Q_vap_to_top == o.M*(o.h_g-o.h_0)); % Eq. (38).
    case 'cold vapor'
        assert(o.Q_vap_to_top < 0, 'Required heat reversal failed: Q=%g W.', o.Q_vap_to_top); % Eqs. (30), (44).
end
assert(~o.warnings.series_not_converged);
text = sprintf('x=%.9g E=%.9g kg/s Q=%.9g W dryout=%d %s', o.x_flash, o.E, o.Q_vap_to_top, o.dryout, residual_text(r));
end

function text = check_zero_height(mode, P)
[s, J] = physical_state('partial flash');
hf = refpropm('H', 'P', s.p_v/1000, 'Q', 0, 'PARAHYD');
hg = refpropm('H', 'P', s.p_v/1000, 'Q', 1, 'PARAHYD');
hc = refpropm('H', 'T', 19, 'P', s.p_v/1000, 'PARAHYD|liquid');
rows = zeros(0, 4);
for h = [hc, hf, hf+0.4*(hg-hf), hg, hg+5e4]
    for H = [0, 0.5*P.TF_heightTiny, P.TF_heightTiny]
        s.h_in = h;
        s.H_ullage = H;
        o = topfill_sources(mode, J, s, P);
        rows(end+1, :) = balance(o, J, s, P); %#ok<AGROW>
        assert(o.E == 0 && o.Q_vap_to_top == 0 && o.Fo == 0 && o.f_cond == 0 && o.t_fall == 0); % Eqs. (34), (38), (46).
        x = min(1, max(0, (h-hf)/(hg-hf))); % Eq. (37): independently verify nozzle-only quality.
        assert(abs(o.x_flash-x) <= 1e-13 && abs(o.J_top_vap-J*x) <= 1e-14);
    end
end
text = sprintf('states=%d H_max=%.3g m flight_heat=0 flight_E=0 %s', size(rows, 1), P.TF_heightTiny, residual_text(max(rows, [], 1)));
end

function text = check_dryout_transition(mode, P)
[s, J] = physical_state('dryout');
options = optimset('Display', 'off'); % assumed numerical setting: default fzero tolerances.
Hdry = fzero(@(H) dry_residual(H, mode, J, s, P), [0, 5], options);
rows = zeros(2, 4);
liquid = zeros(1, 2);
for k = 1:2
    trial = s;
    factors = [0.99, 1.01];
    trial.H_ullage = Hdry*factors(k);
    o = topfill_sources(mode, J, trial, P);
    assert(o.dryout == (k == 2)); % Eq. (38): both sides of the actual transition.
    liquid(k) = o.J_top_liq;
    rows(k, :) = balance(o, J, trial, P);
end
assert(liquid(1) > 0 && liquid(2) == 0);
text = sprintf('H_dry=%.9g m Jliq_before=%.9g after=%.9g kg/s %s', Hdry, liquid(1), liquid(2), residual_text(max(rows, [], 1)));
end

function value = dry_residual(H, mode, J, s, P)
s.H_ullage = H;
o = topfill_sources(mode, J, s, P);
value = o.Q_raw-o.Q_dry; % Eq. (38).
end

function text = check_sweeps(mode, P)
[s, ~] = physical_state('partial flash');
hf = refpropm('H', 'P', s.p_v/1000, 'Q', 0, 'PARAHYD');
hg = refpropm('H', 'P', s.p_v/1000, 'Q', 1, 'PARAHYD');
rows = zeros(0, 4);
for J = [0, 1e-8, 1e-4, 0.01, 0.1, 1]
    for H = [0, 1e-10, 2e-9, 1e-8, 0.05, 0.5, 5]
        s = state(s.p_v, 5, H);
        s.h_in = hf+0.25*(hg-hf);
        o = topfill_sources(mode, J, s, P);
        rows(end+1, :) = balance(o, J, s, P); %#ok<AGROW>
        assert(o.Q_vap_to_top >= 0 && ~o.warnings.series_not_converged);
    end
end
for h = [hf-1, hf, hf+1, hg-1, hg, hg+1]
    s.h_in = h;
    s.H_ullage = 0.1;
    o = topfill_sources(mode, 0.1, s, P);
    rows(end+1, :) = balance(o, 0.1, s, P); %#ok<AGROW>
end
text = sprintf('states=%d J=[0,1] kg/s H=[0,5] m %s', size(rows, 1), residual_text(max(rows, [], 1)));
end

function text = check_conduction(mode, P)
[s, J] = physical_state('subcooled');
base = topfill_sources(mode, J, s, P);
max_error = 0;
max_terms = 0;
for target = [0, 5e-7, 1e-6, 1.001e-6, 1e-4, 0.01, 1]
    if strcmp(mode, 'spray')
        s.H_ullage = target*P.TF_D_d^2*base.v_t/(4*base.a_l); % Eq. (33): choose a test conduction age.
    else
        s.H_ullage = target*J/(pi*base.rho_l*base.a_l); % Eq. (45).
    end
    o = topfill_sources(mode, J, s, P);
    balance(o, J, s, P);
    if o.Fo == 0
        expected = 0;
        assert(o.f_cond == 0 && o.series_terms == 0);
    elseif o.Fo < 1e-6
        if strcmp(mode, 'spray')
            expected = 6*sqrt(o.Fo/pi)-3*o.Fo; % Eq. (34): approved short-time form.
        else
            expected = 4*sqrt(o.Fo/pi)-o.Fo; % Eq. (46): approved short-time form.
        end
        assert(o.series_short_time && o.series_terms == 0);
    else
        expected = full_series_reference(mode, o.Fo);
        assert(~o.series_short_time && ~o.warnings.series_not_converged);
        if strcmp(mode, 'spray')
            next_exponent = (o.series_terms+1)^2*pi^2*o.Fo; % Eq. (34).
        else
            root = reference_bessel_root(o.series_terms+1);
            next_exponent = root^2*o.Fo; % Eq. (46).
        end
        assert(next_exponent > 50, 'Stopped too early: exponent=%g.', next_exponent);
    end
    err = abs(o.f_cond-expected);
    assert(err <= 1e-12, 'Series fraction error=%g at Fo=%g.', err, o.Fo); % assumed numerical setting for the independent fraction audit.
    max_error = max(max_error, err);
    max_terms = max(max_terms, o.series_terms);
end
text = sprintf('ages=7 max_fraction_error=%.9g max_terms=%d short_Fo=5e-7 cutoff=50', max_error, max_terms);
end

function f = full_series_reference(mode, Fo)
% Independent longer sum; cylinder uses fzero for EVERY root, not McMahon.
if strcmp(mode, 'spray')
    n = 1:ceil(sqrt(60/(pi^2*Fo))); % assumed numerical setting: exponent 60 for audit reference.
    f = 1-(6/pi^2)*sum(exp(-n.^2*pi^2*Fo)./n.^2); % Eq. (34).
else
    total = 0;
    for n = 1:ceil(sqrt(60/Fo)/pi+1)
        z = reference_bessel_root(n);
        total = total+4*exp(-z^2*Fo)/z^2; % Eq. (46).
    end
    f = 1-total; % Eq. (46).
end
end

function z = reference_bessel_root(n)
persistent exact
if isempty(exact), exact = zeros(1, 0); end
for k = numel(exact)+1:n
    exact(k) = fzero(@(x) besselj(0, x), [(k-0.5)*pi, k*pi]); % Eq. (46), independent exact-root audit.
end
z = exact(n);
end

function text = check_warnings_and_legacy(mode, P)
[s, J] = physical_state('subcooled');
s.H_ullage = 0.01;
q = P;
q.TF_seriesMaxTerms = 1;
o = topfill_sources(mode, J, s, q);
balance(o, J, s, P);
assert(o.warnings.series_not_converged && o.series_terms == 1, 'Nonconvergence warning was not emitted.');
q = P;
q.initial_ratio_top_bottom = 0.9;
q.bulkevap_ratio_top_bottom = 0.8;
q.ConvCoeffTopfill = 1e9;
q.ETnozzleamout = 100;
a = topfill_sources(mode, J, s, P);
b = topfill_sources(mode, J, s, q);
assert(isequaln(a, b), 'Legacy placeholder values influenced the new module.');
text = sprintf('limited_terms=%d warning=%d legacy_port_difference=0', o.series_terms, o.warnings.series_not_converged);
end

function text = check_case_family(icase, mode, P)
pressures = [45*6894.757293168, 10e5, 10e5, 7e5, 12e5, 6.5e5]; % supplied reviewer case list [Pa].
values = pressures(icase);
if icase == 6, values = [values, 8.6e5]; end
rows = zeros(0, 4);
max_T = 0;
for p = values
    base = state(p, 0, 0.5);
    Ts = base.T_v;
    hs = [base.h_in, refpropm('H', 'T', Ts-2, 'P', p/1000, 'PARAHYD|liquid')]; % Eqs. (15), (37).
    temperatures = Ts+[0, 5, 10];
    if icase == 6, temperatures = [temperatures, 80]; end
    for h = hs
        for Tv = temperatures
            s = state(p, Tv-Ts, 0.5);
            s.h_in = h;
            o = topfill_sources(mode, 0.05, s, P);
            rows(end+1, :) = balance(o, 0.05, s, P); %#ok<AGROW>
            assert(~o.warnings.series_not_converged);
            max_T = max(max_T, Tv);
        end
    end
end
text = sprintf('states=%d p=[%.6g,%.6g] bar Tv_max=%.6g K %s', size(rows, 1), min(values)/1e5, max(values)/1e5, max_T, residual_text(max(rows, [], 1)));
end

function text = check_fig_point(D, target, P)
[s, ~] = physical_state('evaporation');
s = state(s.p_v, 0, 0.5);
q = P;
q.TF_D_d = D;
o = topfill_sources('spray', 0.1, s, q);
v = [o.C_D, o.Re_d, o.v_t];
err = max(abs(v./target-1));
assert(err <= P.TF_testFig12Tol, 'Fig. 12: CD=%g Re=%g v=%g max_rel_err=%g.', v(1), v(2), v(3), err);
assert(o.warnings.diameter_out_of_range == (D < 0.4e-3 || D > 8e-3));
text = sprintf('CD=%.9g Re=%.9g v=%.9g m/s max_rel_error=%.6g%%', v(1), v(2), v(3), 100*err);
end

function text = check_drag_minimum(P)
[s, ~] = physical_state('evaporation');
s = state(s.p_v, 0, 0.5);
options = optimset('TolX', 1e-10, 'Display', 'off'); % [m] assumed numerical setting for the diameter audit.
[D, CD, flag] = fminbnd(@(d) drag_at(d, P, s), 0.4e-3, 1.5e-3, options);
err = max(abs([D/0.88e-3-1, CD/0.38-1]));
assert(flag > 0 && err <= P.TF_testFig12Tol, 'Drag minimum: D=%g m CD=%g error=%g.', D, CD, err);
text = sprintf('D_min=%.9g mm CD_min=%.9g max_rel_error=%.6g%%', 1000*D, CD, 100*err);
end

function CD = drag_at(D, P, s)
P.TF_D_d = D;
o = topfill_sources('spray', 0.1, s, P);
CD = o.C_D;
end

function text = check_reynolds(P)
[s, ~] = physical_state('evaporation');
s = state(s.p_v, 0, 0.5);
maximum = 0;
for basis = {'tenDamme', 'gas'}
    q = P;
    q.TF_ReBasis = basis{1};
    for D = [0.1e-3, 1e-3, 6e-3]
        q.TF_D_d = D;
        o = topfill_sources('spray', 0.1, s, q);
        if strcmp(basis{1}, 'tenDamme')
            Re = o.rho_l*(0.8*D)*o.v_t/o.mu_l; % Eq. (27).
        else
            Re = s.rho_v*D*o.v_t/o.mu_v; % Eq. (27a).
        end
        Nu = 2+0.6*sqrt(Re)*o.Pr_v^(1/3); % Eq. (29): same basis in heat transfer.
        err = max(abs([o.Re_d/Re-1, o.Nu/Nu-1]));
        assert(err < 1e-12, 'Inconsistent Reynolds/Nu basis: error=%g.', err);
        maximum = max(maximum, err);
    end
end
q = P;
q.TF_D_d = 0.02;
o = topfill_sources('spray', 0.1, s, q);
assert(o.warnings.Re_above_2e5 && o.warnings.diameter_out_of_range);
text = sprintf('basis_states=6 max_rel_error=%.9g warning_Re=%.9g diameter_warning=%d', maximum, o.Re_d, o.warnings.diameter_out_of_range);
end

function text = check_jet_area(P)
[s, ~] = physical_state('evaporation');
s.H_ullage = 0.5;
errors = zeros(1, 2);
excess = zeros(1, 2);
for k = 1:2
    flows = [0.1, 0.001];
    o = topfill_sources('jet', flows(k), s, P);
    slender = integral(@(z) pi*sqrt(4*o.M./(pi*o.rho_l*sqrt(o.w_0^2+2*P.g*z))), 0, s.H_ullage, ...
        'RelTol', 1e-10, 'AbsTol', 1e-14); % Eq. (41); assumed numerical setting for independent quadrature.
    exact = integral(@(z) direct_surface(z, o.M, o.rho_l, o.w_0, P.g), 0, s.H_ullage, ...
        'RelTol', 1e-10, 'AbsTol', 1e-14); % Eq. (42); assumed numerical setting for independent z-quadrature.
    errors(k) = max(abs([o.A_j/slender-1, o.A_geom/exact-1]));
    excess(k) = o.A_geom/o.A_j-1;
    assert(errors(k) < 1e-9, 'Jet area quadrature error=%g.', errors(k)); % assumed numerical setting for cross-parameterization agreement.
    assert(o.jet_slender_check_assessed && o.warnings.jet_slender_geometry_failed == (excess(k) > 0.01)); % Eq. (42): assumed diagnostic cutoff.
end
assert(excess(1) < 0.01 && excess(2) > 0.01, 'Area-warning test did not cover both sides: %g, %g.', excess(1), excess(2));
q = P;
q.g = 0;
c = topfill_sources('jet', 0.1, s, q);
assert(abs(c.A_j/(pi*q.TF_D_0*s.H_ullage)-1) < 1e-12 && c.A_geom == c.A_j); % Eqs. (41)-(42).
assert(abs(c.t_fall/(s.H_ullage/c.w_0)-1) < 1e-12); % Eq. (40).
text = sprintf('area_rel_error_max=%.9g excess=[%.9g,%.9g] g0_A=%.9g m^2', max(errors), excess(1), excess(2), c.A_geom);
end

function value = direct_surface(z, M, rho_l, w0, g)
w = sqrt(w0^2+2*g*z); % Eq. (39).
R = sqrt(M./(pi*rho_l*w)); % Eqs. (39), (42).
slope = -g*R./(2*w.^2); % Eqs. (39), (42).
value = 2*pi*R.*sqrt(1+slope.^2); % Eq. (42), direct independent integrand.
end

function text = check_host_rates(P)
[s, ~] = physical_state('condensation');
Jtr = 0.1; C0 = 0.002; Jevap = 0.001; Jvent = 0.003;
rhoL = 70; WV = 23; WL = 19; VS = 7; LS = 11;
hcd = 5e5; hvent = 6e5; vvent = 4; % Arbitrary SI algebraic test record, not physical defaults.
ein = s.h_in+s.v_in^2/2; % Eq. (1).
max_mass = 0; max_energy = 0; count = 0;
for mode = {'spray', 'jet'}
    for pump = [0, 30]
        for r = [0, 1e-8, 0.3, 1-1e-8, 1]
            Jtop = r*Jtr; Jbot = (1-r)*Jtr; % Eq. (47).
            o = topfill_sources(mode{1}, Jtop, s, P);
            balance(o, Jtop, s, P);
            JL = Jbot+o.J_top_liq+C0-Jevap; % Eqs. (21)-(22).
            JV = o.J_top_vap-Jvent-C0+Jevap; % Eq. (22).
            W = -s.p_v*JL/rhoL; % Eq. (22).
            QL = WL-LS+W+pump+Jbot*ein+o.H_top_liq+C0*hcd-Jevap*hcd; % Eq. (23).
            QV = WV-VS-W+o.H_top_vap-o.Q_vap_to_top-Jvent*(hvent+vvent^2/2)-C0*hcd+Jevap*hcd; % Eq. (23).
            expected = WL+WV-LS-VS+pump+Jtr*ein-Jvent*(hvent+vvent^2/2); % Eq. (48).
            em = abs(JL+JV-(Jtr-Jvent))/max(P.TF_J_scale, Jtr); % Eq. (48), throughput-normalized algebraic audit.
            ee = abs(QL+QV-expected)/max([P.TF_H_scale, abs(QL), abs(QV), abs(expected)]);
            assert(em <= P.TF_testMassTol && ee <= P.TF_testEnergyTol, 'Host identity residuals: em=%g ee=%g.', em, ee);
            if r == 0
                assert(JL == Jtr+C0-Jevap && JV == -Jvent-C0+Jevap); % Eq. (49).
            elseif r == 1
                assert(Jbot == 0 && Jbot*ein == 0); % Eqs. (21), (47).
            end
            max_mass = max(max_mass, em); max_energy = max(max_energy, ee); count = count+1;
        end
    end
end
text = sprintf('states=%d max_normalized_mass=%.9g energy=%.9g', count, max_mass, max_energy);
end

function text = check_errors(P)
[s, ~] = physical_state('evaporation');
pc = 1000*refpropm('P', 'C', 0, ' ', 0, 'PARAHYD');
count = 0;
for mode = {'spray', 'jet'}
    for p = [pc, 1.01*pc]
        bad = s; bad.p_v = p;
        expect_error(@() topfill_sources(mode{1}, 0.1, bad, P), 'topfill_sources:AboveCriticalPressure');
        count = count+1;
    end
end
bad = s; bad.H_ullage = -1;
expect_error(@() topfill_sources('jet', 0.1, bad, P), 'topfill_sources:BadState');
bad = s; bad.p_v = 1;
expect_error(@() topfill_sources('spray', 0.1, bad, P), 'topfill_sources:PropertyState');
q = P; q.g = 1e-16;
expect_error(@() topfill_sources('spray', 0.1, s, q), 'topfill_sources:NoTerminalRoot');
q = P; q.TF_rootMaxFunEvals = 1;
expect_error(@() topfill_sources('spray', 0.1, s, q), 'topfill_sources:NoTerminalRoot');
text = sprintf('expected_errors=%d pcrit=%.9g Pa fixed_bracket=[1e-6,50] m/s', count+4, pc);
end

function expect_error(f, identifier)
try
    f();
catch cause
    assert(strcmp(cause.identifier, identifier), 'Expected %s, got %s: %s', identifier, cause.identifier, cause.message);
    return;
end
error('test_topfill_sources:MissingExpectedError', 'Expected %s was not raised.', identifier);
end

function s = state(p, excess, H)
[T, h] = refpropm('TH', 'P', p/1000, 'Q', 0, 'PARAHYD'); % Eq. (15).
Tv = T+excess;
rho = refpropm('D', 'T', Tv, 'P', p/1000, 'PARAHYD|gas'); % Specified phase-continuous bulk gas for the test state.
s = struct('h_in', h, 'v_in', 3, 'p_v', p, 'T_v', Tv, 'rho_v', rho, 'H_ullage', H);
end

function v = ports(o)
v = [o.J_top_liq, o.J_top_vap, o.H_top_liq, o.H_top_vap, o.Q_vap_to_top];
end

function finite_output(o)
for name = fieldnames(o)'
    v = o.(name{1});
    if isnumeric(v)
        assert(isreal(v) && all(isfinite(v(:))), 'Non-real/non-finite diagnostic %s.', name{1});
    elseif isstruct(v)
        finite_output(v);
    end
end
end

function r = balance(o, J, s, P)
finite_output(o);
assert(o.x_flash >= 0 && o.x_flash <= 1 && o.J_top_liq >= 0);
Rm = o.J_top_liq+o.J_top_vap-J; % Eq. (51): dimensional residual [kg/s].
RE = o.H_top_liq+o.H_top_vap-J*(s.h_in+s.v_in^2/2)-o.Q_vap_to_top; % Eq. (51): dimensional residual [W].
ms = max([P.TF_J_scale, abs(J), abs(o.J_top_liq), abs(o.J_top_vap)]); % Eq. (52).
es = max([P.TF_H_scale, abs(J*(s.h_in+s.v_in^2/2)), abs(o.H_top_liq), abs(o.H_top_vap), abs(o.Q_vap_to_top)]); % Eq. (52).
em = abs(Rm)/ms; ee = abs(RE)/es; % Eq. (52).
assert(em <= P.TF_testMassTol && ee <= P.TF_testEnergyTol, ...
    '|Rm|=%.9g kg/s |RE|=%.9g W em=%.9g ee=%.9g (limits %.3g,%.3g).', abs(Rm), abs(RE), em, ee, P.TF_testMassTol, P.TF_testEnergyTol);
if J > 0
    static = o.J_top_liq*o.h_bar+o.F*o.h_g0+o.E*o.h_g; % Eqs. (16)-(17): independent constituent static-flow sum.
    sr = static-J*s.h_in-o.Q_vap_to_top;
    kr = o.K_l+o.K_v-J*s.v_in^2/2; % Eq. (18), independent kinetic allowance sum.
    assert(abs(sr)/es <= P.TF_testEnergyTol && abs(kr)/es <= P.TF_testEnergyTol, 'Static/kinetic residuals: %g, %g W.', sr, kr);
end
r = [abs(Rm), abs(RE), em, ee];
end

function text = residual_text(r)
text = sprintf('|Rm|=%.3g kg/s |RE|=%.3g W em=%.3g ee=%.3g', r(1), r(2), r(3), r(4));
end

function text = check_reference_shifts(mode, P)
original_dir = pwd;
original_path = path;
base = fileread(which('refpropm'));
base = regexprep(base, 'function\s+varargout\s*=\s*refpropm\(', 'function varargout = tf_reference_base(', 'once');
assert(contains(base, 'function varargout = tf_reference_base('), 'Reference audit requires the supplied varargout shim.');
kinds = {'condensation', 'partial flash', 'all vapor', 'evaporation', 'dryout', 'cold vapor'};
examples = cell(size(kinds));
for k = 1:numel(kinds)
    [s, J] = physical_state(kinds{k});
    examples{k} = struct('s', s, 'J', J, 'o', topfill_sources(mode, J, s, P));
end
max_invariant = 0; max_port_shift = 0; rows = zeros(0, 4);
for shift = [-1e6, 1e6] % [J/kg] assumed numerical setting for reference-invariance audit.
    temporary = tempname;
    mkdir(temporary);
    cleanup = onCleanup(@() restore_reference(original_dir, original_path, temporary));
    write_text(fullfile(temporary, 'tf_reference_base.m'), base);
    wrapper = sprintf([ ...
        'function varargout = refpropm(prop, s1, v1, s2, v2, varargin)\n' ...
        'shift = %.17g;\n' ...
        'if strcmpi(strtrim(s1), ''H''), v1 = v1-shift; end\n' ...
        'if strcmpi(strtrim(s2), ''H''), v2 = v2-shift; end\n' ...
        'varargout = cell(1, nargout);\n' ...
        '[varargout{:}] = tf_reference_base(prop, s1, v1, s2, v2, varargin{:});\n' ...
        'for k = 1:nargout\n' ...
        '    if any(lower(prop(k)) == ''hu''), varargout{k} = varargout{k}+shift; end\n' ...
        'end\nend\n'], shift);
    write_text(fullfile(temporary, 'refpropm.m'), wrapper);
    addpath(temporary, '-begin');
    cd(temporary);
    clear refpropm tf_reference_base
    rehash;
    for k = 1:numel(examples)
        e = examples{k}; a = e.o;
        s = e.s; s.h_in = s.h_in+shift;
        b = topfill_sources(mode, e.J, s, P);
        rows(end+1, :) = balance(b, e.J, s, P); %#ok<AGROW>
        for field = {'x_flash', 'F', 'M', 'E', 'Q_vap_to_top', 'J_top_liq', 'J_top_vap', 'Fo', 'f_cond'}
            name = field{1};
            err = abs(b.(name)-a.(name))/max(1, abs(a.(name)));
            max_invariant = max(max_invariant, err);
            assert(err <= 1e-9, 'Reference-dependent %s: error=%g.', name, err); % assumed numerical setting for invariant-state audit.
        end
        err = max(abs([b.H_top_liq-a.H_top_liq-shift*a.J_top_liq, b.H_top_vap-a.H_top_vap-shift*a.J_top_vap])); % Section 8: signed energy-port shifts.
        max_port_shift = max(max_port_shift, err);
        assert(err <= 1e-6, 'Signed energy-port reference-shift error=%g W.', err); % [W] assumed numerical setting for reference subtraction roundoff.
    end
    clear cleanup
end
text = sprintf('states=%d shifts=[-1e6,+1e6] J/kg max_invariant=%.3g max_port_error=%.3g W %s', size(rows, 1), max_invariant, max_port_shift, residual_text(max(rows, [], 1)));
end

function write_text(file, text)
fid = fopen(file, 'w');
assert(fid >= 0, 'Could not create isolated reference-test file.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', text);
end

function restore_reference(folder, old_path, temporary)
cd(folder);
path(old_path);
clear refpropm tf_reference_base
rehash;
if isfolder(temporary), rmdir(temporary, 's'); end
end
