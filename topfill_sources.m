function out = topfill_sources(mode, J_top, s, P)
%TOPFILL_SOURCES Conservative five-port top inlet, specification revision 3.
% out = topfill_sources('spray'|'jet', J_top, s, P)
% s: h_in [J/kg], v_in [m/s], p_v [Pa], T_v [K], rho_v [kg/m^3],
%    H_ullage [m]. The host supplies its actual delivered inlet state.
% P: P.g and the TF_* register in Parameters_topfill_defaults.
% Saturation uses PARAHYD; gas-film T,P calls use PARAHYD|gas and liquid
% T,P calls use PARAHYD|liquid, including metastable phase continuation.
% refpropm pressure is kPa and viscosity is Pa*s. No host state is changed.
% Persistent storage below contains mathematical Bessel roots only.
%
% Numerical evaluation follows the user's completion decisions: exponent
% cutoff 50, short-time conduction below Fo=1e-6, exact first 20 J0 roots,
% McMahon roots thereafter, and exact-area diagnostic for jet slenderness.

require_finite(J_top, 'J_top');
out = empty_output();
if J_top <= 0
    return; % Eq. (38), Section 4.4: five exact zeros before every division/property call.
end

mode = text_choice(mode, {'spray', 'jet'}, 'mode');
if ~isstruct(s) || ~isscalar(s)
    error('topfill_sources:BadState', 's must be a scalar ET state struct.');
end
fields = {'h_in', 'v_in', 'p_v', 'T_v', 'rho_v', 'H_ullage'};
for k = 1:numel(fields)
    if ~isfield(s, fields{k})
        error('topfill_sources:BadState', 'Missing ET state s.%s.', fields{k});
    end
    require_finite(s.(fields{k}), ['s.' fields{k}]);
end
if s.p_v <= 0 || s.T_v <= 0 || s.rho_v <= 0 || s.H_ullage < 0
    error('topfill_sources:BadState', ...
        'Require p_v > 0, T_v > 0, rho_v > 0 and H_ullage >= 0; received %.16g Pa, %.16g K, %.16g kg/m^3, %.16g m.', ...
        s.p_v, s.T_v, s.rho_v, s.H_ullage);
end
P = Parameters_topfill_defaults(P);
out.mode = mode;
out.ReBasis = text_choice(P.TF_ReBasis, {'tenDamme', 'gas'}, 'P.TF_ReBasis');

p_kPa = s.p_v/1000; % Eq. (15): pressure-unit conversion only at the property interface.
p_crit = 1000*properties('P', 'C', 0, ' ', 0); % Eq. (15), Section 1: EOS critical boundary [Pa].
require_positive_property(p_crit, 'critical pressure');
out.p_crit = p_crit;
if s.p_v >= p_crit
    error('topfill_sources:AboveCriticalPressure', ...
        'p_v = %.16g Pa is at or above para-H2 p_crit = %.16g Pa; Eq. (15) has no liquid-vapor saturation state.', ...
        s.p_v, p_crit);
end
[T_star, h_f] = properties('TH', 'P', p_kPa, 'Q', 0); % Eq. (15): new saturated liquid at current p_v.
h_g = properties('H', 'P', p_kPa, 'Q', 1); % Eq. (15): new saturated vapor at current p_v.
L_star = h_g-h_f; % Eq. (15): latent heat on the new interface only.
require_positive_property(T_star, 'T_star');
require_positive_property(L_star, 'h_g-h_f');
out.T_star = T_star;
out.h_f = h_f;
out.h_g = h_g;
out.L_star = L_star;

x_flash = min(1, max(0, (s.h_in-h_f)/L_star)); % Eq. (37): static-enthalpy flash, without inlet kinetic energy.
F = x_flash*J_top; % Eq. (37): nozzle vapor flow.
M = (1-x_flash)*J_top; % Eq. (37): residual incoming liquid flow.
out.x_flash = x_flash;
out.F = F;
out.M = M;
if s.h_in >= h_g
    out.h_g0 = s.h_in; % Eq. (37): preserve all-vapor superheat.
    out.J_top_vap = J_top; % Eq. (38), Section 4.4: no liquid-surface exposure.
    out.K_v = J_top*(s.v_in^2/2); % Eq. (18): all kinetic allowance accompanies outgoing vapor.
    out.H_top_vap = J_top*(s.h_in+s.v_in^2/2); % Eqs. (19), (37): full static inlet enthalpy and retained kinetic allowance.
    assert_finite_output(out);
    return;
end
if s.h_in < h_f
    h_0 = s.h_in; % Eq. (37): retain inlet subcooling.
else
    h_0 = h_f; % Eq. (37): saturated liquid after partial flash.
end
h_g0 = h_g; % Eq. (37): flashed vapor is saturated (unused if F = 0).
out.h_0 = h_0;
out.h_g0 = h_g0;
out.Q_dry = M*(h_g-h_0); % Eq. (38): liquid-stream complete-evaporation requirement, including the zero-height diagnostic.
h_bar = h_0; % Eqs. (35), (46): exact zero-age liquid enthalpy.
E = 0; % Eq. (38), Section 4.4: no flight phase change at zero height.
Q = 0; % Eq. (38), Section 4.4: no flight heat at zero height.

if s.H_ullage > 0
    require_control(P, 'TF_heightTiny', false, true);
    no_flight = s.H_ullage <= P.TF_heightTiny; % Eq. (38), Section 4.4: specified numerical zero-height dispatch.
else
    no_flight = true; % Eq. (38), Section 4.4: exact zero-height endpoint needs no numerical choice.
end

if ~no_flight
    validate_flight_controls(P, mode);

    if h_0 == h_f
        T_0 = T_star; % Eqs. (15), (37): saturated residual liquid.
        if strcmp(mode, 'spray')
            [rho_l, mu_l, k_l, cp_l] = properties('DVLC', 'P', p_kPa, 'Q', 0); % Eqs. (27), (33): liquid saturation root, avoiding ambiguous T,P.
        else
            [rho_l, k_l, cp_l] = properties('DLC', 'P', p_kPa, 'Q', 0); % Eqs. (33), (39): jet has no liquid-viscosity closure.
            mu_l = 0; % Unused jet diagnostic: do not request an unnecessary property.
        end
    else
        if strcmp(mode, 'spray')
            [T_0, rho_l, mu_l] = properties('TDV', 'P', p_kPa, 'H', h_0); % Eq. (37), Section 7: actual post-flash liquid properties.
        else
            [T_0, rho_l] = properties('TD', 'P', p_kPa, 'H', h_0); % Eq. (37), Section 7: jet needs no liquid viscosity.
            mu_l = 0; % Unused jet diagnostic.
        end
        T_l_mean = (T_0+T_star)/2; % Eq. (35), Section 7: frozen liquid mean-temperature rule.
        if T_l_mean == T_star
            [k_l, cp_l] = properties('LC', 'P', p_kPa, 'Q', 0); % Eqs. (33), (35): exact saturation endpoint.
        else
            [k_l, cp_l] = properties('LC', 'T', T_l_mean, 'P', p_kPa, 'PARAHYD|liquid'); % Eqs. (33), (35), Section 7: mean-temperature liquid root, including its continuation.
        end
    end
    require_positive_property(T_0, 'post-flash liquid temperature');
    require_positive_property(rho_l, 'post-flash liquid density');
    if strcmp(mode, 'spray')
        require_positive_property(mu_l, 'post-flash liquid viscosity [Pa*s]');
    end
    require_positive_property(k_l, 'mean-liquid conductivity');
    require_positive_property(cp_l, 'mean-liquid heat capacity');
    if T_0 > T_star
        error('topfill_sources:PropertyState', ...
            'EOS post-flash liquid T = %.16g K exceeds T_star = %.16g K for h_0 <= h_f.', T_0, T_star);
    end
    a_l = k_l/(rho_l*cp_l); % Eq. (33): frozen liquid diffusivity.
    T_film = (s.T_v+T_star)/2; % Section 4.1/7 property rule used by Eqs. (29), (44).
    if strcmp(mode, 'jet')
        gas_codes = 'VLCB';
    else
        gas_codes = 'VLC';
    end
    gas_values = cell(1, numel(gas_codes));
    [gas_values{:}] = properties(gas_codes, 'T', T_film, 'P', p_kPa, 'PARAHYD|gas'); % Eqs. (29), (44), Section 7: continuously selected gas film at p_v, including T_v < T_star.
    mu_v = gas_values{1};
    k_v = gas_values{2};
    cp_v = gas_values{3};
    require_positive_property(mu_v, 'gas-film viscosity [Pa*s]');
    require_positive_property(k_v, 'gas-film conductivity');
    require_positive_property(cp_v, 'gas-film heat capacity');
    Pr_v = mu_v*cp_v/k_v; % Eqs. (29), (44): viscosity/diffusivity ratio, with density cancelling.
    out.T_0 = T_0;
    out.rho_l = rho_l;
    out.mu_l = mu_l;
    out.a_l = a_l;
    out.T_film = T_film;
    out.mu_v = mu_v;
    out.k_v = k_v;
    out.cp_v = cp_v;
    out.Pr_v = Pr_v;

    if strcmp(mode, 'spray')
        D_d = P.TF_D_d; % Eq. (24), Section 7: supplied representative diameter.
        V_d = pi*D_d^3/6; % Eq. (24): sphere volume.
        S_d = pi*D_d^2; % Eq. (24): sphere surface area.
        if rho_l <= s.rho_v || P.g <= 0
            error('topfill_sources:NoTerminalRoot', ...
                'Downward terminal fall needs rho_l > rho_v and g > 0; got %.16g, %.16g kg/m^3 and %.16g m/s^2.', rho_l, s.rho_v, P.g);
        end
        if strcmp(out.ReBasis, 'tenDamme')
            Re_per_v = rho_l*(0.8*D_d)/mu_l; % Eq. (27): liquid properties and capillary-tip diameter for drag AND heat transfer.
        else
            Re_per_v = s.rho_v*D_d/mu_v; % Eq. (27a): gas-basis sensitivity, full sphere diameter.
        end
        [v_t, Re_d, C_D, root_iterations, v_guess] = terminal_speed(D_d, rho_l, s.rho_v, Re_per_v, P);
        t_fall = s.H_ullage/v_t; % Eq. (27a): terminal-speed exposure time.
        N_dot = M/(rho_l*V_d); % Eq. (28): count only post-flash liquid, with no extra nozzle multiplier.
        N_flight = N_dot*t_fall; % Eq. (28): algebraic exposure; no stored inventory.
        Nu = 2+0.6*sqrt(Re_d)*Pr_v^(1/3); % Eq. (29): same selected Reynolds basis as drag.
        h_transfer = Nu*k_v/D_d; % Eq. (29): external heat-transfer coefficient.
        Q_raw = h_transfer*S_d*(s.T_v-T_star)*t_fall*N_dot; % Eq. (30): signed raw gas heat.
        Fo = 4*a_l*t_fall/D_d^2; % Eq. (33): radius-based Fourier number, with squared diameter.
        [f_cond, series_terms, series_bound, converged, short_time] = conduction_fraction('spray', Fo, P);
        h_bar = h_0+f_cond*(h_f-h_0); % Eq. (35): full sphere-series enthalpy adaptation.
        out.D_d = D_d;
        out.V_d = V_d;
        out.S_d = S_d;
        out.v_t = v_t;
        out.Re_d = Re_d;
        out.C_D = C_D;
        out.N_dot = N_dot;
        out.N_flight = N_flight;
        out.root_iterations = root_iterations;
        out.v_guess = v_guess;
        out.warnings.diameter_out_of_range = D_d < 0.4e-3 || D_d > 8e-3; % Section 4.1/7 diagnostic, not a physics gate.
        out.warnings.Re_above_2e5 = Re_d > 2e5; % Section 4.1/7 diagnostic, not an admissible-Re gate.
    else
        beta_v = gas_values{4}; % Eq. (44): expansion coefficient from the same gas-film state.
        require_positive_property(beta_v, 'gas-film expansion coefficient');
        D_0 = P.TF_D_0; % Eq. (39): effective post-flash coherent core diameter.
        w_0 = 4*M/(pi*rho_l*D_0^2); % Eq. (39): coherent-core inlet velocity from continuity.
        w_H = hypot(w_0, sqrt(2*P.g*s.H_ullage)); % Eq. (39): gravity-accelerated impact velocity.
        D_H = sqrt(4*M/(pi*rho_l*w_H)); % Eq. (39): coherent-core diameter at impact.
        t_fall = 2*s.H_ullage/(w_H+w_0); % Eq. (40): stable residence time; also valid at g = 0.
        speed_ratio = w_0/w_H; % Eq. (41): algebraic factorization for stable area evaluation.
        A_j = (4*pi*s.H_ullage/3)*D_H*(1+sqrt(speed_ratio)+speed_ratio)/((1+speed_ratio)*(1+sqrt(speed_ratio))); % Eq. (41): identical slender area without subtracting similar powers; g = 0 gives pi*D_0*H.
        max_slope = P.g*D_0/(4*w_0^2); % Eqs. (39), (42): max(abs(dR_j/dz)) occurs at the nozzle.
        A_geom = exact_jet_area(A_j, M, rho_l, D_0, D_H, w_0, s.H_ullage, P); % Eq. (42): exact surface, used only for the diagnostic.
        area_excess = A_geom/A_j-1; % Eq. (42): quantify the slender-area approximation.
        alpha_v = k_v/(s.rho_v*cp_v); % Eq. (44): inherited bulk vapor density in transport scaling.
        nu_v = mu_v/s.rho_v; % Eq. (44): gas kinematic viscosity.
        Ra_g = P.g*beta_v*abs(s.T_v-T_star)*P.TF_ell_g^3/(nu_v*alpha_v); % Eq. (44): fixed gas-layer reference length.
        Nu = (0.825+0.387*Ra_g^(1/6)/(1+(0.492/Pr_v)^(9/16))^(8/27))^2; % Eq. (43): squared Churchill-Chu plate correlation.
        h_transfer = P.TF_C_j*k_v/P.TF_ell_g*Nu; % Eq. (44): declared screening adaptation.
        Q_raw = h_transfer*A_j*(s.T_v-T_star); % Eq. (44): signed heat over slender jet area.
        Fo = pi*rho_l*a_l*s.H_ullage/M; % Eq. (45): contracting-cylinder conduction age.
        [f_cond, series_terms, series_bound, converged, short_time] = conduction_fraction('jet', Fo, P);
        h_bar = h_0+f_cond*(h_f-h_0); % Eq. (46): full Bessel-series enthalpy adaptation.
        out.D_0 = D_0;
        out.w_0 = w_0;
        out.w_H = w_H;
        out.D_H = D_H;
        out.A_j = A_j;
        out.A_geom = A_geom;
        out.jet_area_excess = area_excess;
        out.max_jet_slope = max_slope;
        out.Ra_g = Ra_g;
        out.beta_v = beta_v;
        out.jet_slender_check_assessed = true;
        out.warnings.jet_slender_geometry_failed = area_excess > P.TF_jetAreaExcessLimit; % Eq. (42): assumed diagnostic cutoff; no change to Eq. (44) heat-transfer area.
    end
    require_finite(Fo, 'conduction age Fo');
    require_finite(Q_raw, 'raw flight heat Q_raw');
    out.t_fall = t_fall;
    out.Nu = Nu;
    out.h_transfer = h_transfer;
    out.Fo = Fo;
    out.f_cond = f_cond;
    out.series_terms = series_terms;
    out.series_error_bound = series_bound;
    out.series_short_time = short_time;
    out.warnings.series_not_converged = ~converged; % Section 4.3/5.4/7: diagnostic only, never an error.
    out.Q_raw = Q_raw;
    Q_dry = out.Q_dry; % Eq. (38): complete-evaporation heat requirement, evaluated once.
    if Q_raw >= Q_dry
        Q = Q_dry; % Eq. (38): terminate liquid-surface exposure at complete evaporation.
        E = M; % Eq. (38): full residual-liquid evaporation, without a separate mass clip.
        out.dryout = true;
    else
        Q = Q_raw; % Eq. (38): preserve signed flight heat below dryout.
        denominator = h_g-h_bar; % Eq. (17): vapor-to-arriving-liquid enthalpy difference.
        require_positive_property(denominator, 'h_g-h_bar');
        E = (Q-M*(h_bar-h_0))/denominator; % Eq. (17): evaporation-positive mass exchange, condensation unbounded.
    end
end

out.h_bar = h_bar;
out.E = E;
out.Q_vap_to_top = Q;
out.J_top_liq = M-E; % Eq. (17): delivered liquid includes condensed ullage mass.
out.J_top_vap = F+E; % Eq. (17): signed vapor contribution, potentially negative.
K_in = J_top*(s.v_in^2/2); % Eq. (18): separate inlet kinetic allowance.
B = out.J_top_liq+max(out.J_top_vap, 0); % Eq. (18): positive outgoing mass; never divide by net vapor flow.
require_positive_property(B, 'positive outgoing mass B');
out.K_l = K_in*out.J_top_liq/B; % Eq. (18): kinetic allocation to positive liquid outflow.
out.K_v = K_in*max(out.J_top_vap, 0)/B; % Eq. (18): kinetic allocation to positive vapor outflow.
out.H_top_liq = (M-E)*h_bar+out.K_l; % Eq. (19): signed stream enthalpy plus kinetic allowance.
out.H_top_vap = F*h_g0+E*h_g+out.K_v; % Eq. (19): constituent vapor flows, including negative condensation.
if out.dryout
    out.J_top_liq = 0; % Eq. (38): exact simultaneous liquid-port zeros at dryout.
    out.H_top_liq = 0; % Eq. (38): no residual liquid enthalpy port.
end
if out.J_top_liq < 0
    error('topfill_sources:NumericalState', ...
        'Eq. (38) should prevent negative liquid flow; received %.16g kg/s.', out.J_top_liq);
end
assert_finite_output(out);
end

function [v, Re, C_D, iterations, guess] = terminal_speed(D, rho_l, rho_v, Re_per_v, P)
force_scale = 4*P.g*D*(rho_l-rho_v)/(3*rho_v); % Eqs. (25), (27a): terminal force scale.
guess = sqrt(force_scale/0.47); % Eq. (27a), Section 4.1: initial C_D=0.47 estimate.
require_positive_property(guess, 'initial terminal-velocity estimate');
residual = @(trial) brauer(Re_per_v*trial)*(trial/guess)^2-0.47; % Eqs. (25)-(27a): force balance normalized by the initial estimate.
bracket = P.TF_velocityBracket;
a = residual(bracket(1));
b = residual(bracket(2));
require_finite(a, 'lower-bracket terminal force residual');
require_finite(b, 'upper-bracket terminal force residual');
if a ~= 0 && b ~= 0 && sign(a) == sign(b)
    error('topfill_sources:NoTerminalRoot', ...
        'Eq. (25) has no sign change on [%.16g, %.16g] m/s: residuals %.16g, %.16g; C_D=0.47 estimate %.16g m/s.', ...
        bracket(1), bracket(2), a, b, guess);
end
[v, info] = bounded_fzero(residual, bracket, P, 'topfill_sources:NoTerminalRoot'); % Eqs. (25)-(27a): specified bracket and default fzero tolerances.
require_positive_property(v, 'terminal velocity');
Re = Re_per_v*v; % Eqs. (27), (27a): identical Reynolds basis used in Eq. (29).
C_D = brauer(Re); % Eq. (26): restored Brauer correlation.
require_positive_property(C_D, 'terminal C_D');
iterations = info.iterations;
end

function C_D = brauer(Re)
require_positive_property(Re, 'droplet Reynolds number');
C_D = 24/Re+3.72/sqrt(Re)-(4.83e-3*sqrt(Re))/(1+3e-6*Re*sqrt(Re))+0.49; % Eq. (26): constant and denominator exactly as revision 3.
end

function A_geom = exact_jet_area(A_slender, M, rho_l, D_0, D_H, w_0, H, P)
require_positive_property(A_slender, 'slender jet area');
if P.g == 0
    A_geom = A_slender; % Eqs. (41)-(42): exact cylindrical zero-gravity limit.
    return;
end
R_0 = D_0/2; % Eqs. (39), (42): nozzle radius.
R_H = D_H/2; % Eqs. (39), (42): impact radius.
K = M/(pi*rho_l); % Eq. (39): continuity gives R^2*w = K.
q = 2*P.g*H/w_0^2; % Eq. (39): dimensionless speed-squared increment.
delta_R = R_0*(-expm1(-0.25*log1p(q))); % Eqs. (39)-(42): stable R_0-R_H, even at small height.
% Eq. (42), algebraic rearrangement: A_geom=A_slender+integral of
% 2*pi*R/(hypot(1,dz/dR)+abs(dz/dR)) dR. The bounded correction avoids
% missing a very steep, very short nozzle contraction in z-quadrature.
correction = integral(@(u) area_correction(u, R_H, delta_R, K, P.g), 0, 1, ...
    'RelTol', P.TF_areaRelTol, 'AbsTol', P.TF_areaAbsTol); % Eq. (42): assumed numerical setting for exact-area quadrature.
A_geom = A_slender+correction; % Eq. (42): exact surface used only as a diagnostic.
require_positive_property(A_geom, 'exact geometric jet area');
end

function value = area_correction(u, R_H, delta_R, K, g)
R = R_H+delta_R*u; % Eq. (42): normalized radius integration coordinate.
dz_dR = 2*K^2./(g*R.^5); % Eqs. (39), (42): magnitude of axial slope in radius coordinates.
value = 2*pi*R*delta_R./(hypot(1, dz_dR)+dz_dR); % Eq. (42): stable exact area correction, not a new area closure.
end

function [fraction, terms, tail, converged, short_time] = conduction_fraction(mode, Fo, P)
require_finite(Fo, 'conduction age Fo');
if Fo < 0
    error('topfill_sources:NumericalState', 'Conduction age must be nonnegative.');
end
terms = 0;
tail = 0;
converged = true;
short_time = false;
if Fo == 0
    fraction = 0; % Eqs. (34), (46): exact zero-age endpoint.
    return;
elseif Fo < P.TF_shortTimeFo
    short_time = true;
    if strcmp(mode, 'spray')
        fraction = 6*sqrt(Fo/pi)-3*Fo; % Eq. (34): user-selected short-time numerical form; assumed numerical setting.
    else
        fraction = 4*sqrt(Fo/pi)-Fo; % Eq. (46): user-selected short-time numerical form; assumed numerical setting.
    end
    return;
end
sum_terms = 0;
compensation = 0;
converged = false;
for n = 1:P.TF_seriesMaxTerms+1
    if strcmp(mode, 'spray')
        exponent = n^2*pi^2*Fo; % Eq. (34): full sphere eigenvalue exponent.
        weight = (6/pi^2)/n^2; % Eq. (34): full sphere eigenfunction weight.
        tail = (6/pi^2)*(1/n+1/n^2)*exp(-exponent); % Eq. (34): omitted-tail bound including the first omitted term.
    else
        zeta = bessel_root(n, P);
        exponent = zeta^2*Fo; % Eq. (46): cylinder eigenvalue exponent.
        weight = 4/zeta^2; % Eq. (46): cylinder eigenfunction weight.
        tail = (4/pi^2)*(1/(n-0.5)+1/(n-0.5)^2)*exp(-exponent); % Eq. (46): omitted-tail estimate; excludes McMahon and roundoff error.
    end
    if exponent > P.TF_seriesExponentLimit
        converged = true; % Eqs. (34), (46): assumed numerical setting, exponent cutoff 50.
        break;
    elseif n > P.TF_seriesMaxTerms
        break; % Section 7: bounded work; nonconvergence is a warning only.
    end
    term = weight*exp(-exponent); % Eqs. (34), (46): one term of the full series.
    y = term-compensation;
    updated_sum = sum_terms+y;
    compensation = (updated_sum-sum_terms)-y;
    sum_terms = updated_sum;
    terms = n;
end
fraction = 1-sum_terms; % Eqs. (34), (46): full-series response, never clipped.
if ~finite_scalar(fraction) || fraction < 0 || fraction > 1
    error('topfill_sources:NumericalState', ...
        'Conduction series produced invalid fraction %.16g at Fo %.16g.', fraction, Fo);
end
end

function zeta = bessel_root(n, P)
persistent exact_roots
if n > P.TF_exactBesselRoots
    beta = (n-0.25)*pi; % Eq. (46): McMahon phase for J0 roots.
    zeta = beta+1/(8*beta)-31/(384*beta^3)+3779/(15360*beta^5)-6277237/(3440640*beta^7); % Eq. (46): McMahon through beta^-7; assumed numerical setting. NIST DLMF 10.21.19, nu=0: https://dlmf.nist.gov/10.21.E19
    return;
end
if isempty(exact_roots)
    exact_roots = zeros(1, 0);
end
for k = numel(exact_roots)+1:n
    bracket = [(k-0.5)*pi, k*pi]; % Eq. (46): bracket the kth positive J0 root.
    [root, ~] = bounded_fzero(@(x) besselj(0, x), bracket, P, 'topfill_sources:BesselRootFailure'); % Eq. (46): first 20 roots computed once by fzero on besselj(0,.).
    if root <= bracket(1) || root >= bracket(2)
        error('topfill_sources:BesselRootFailure', 'J0 root %d is outside its bracket.', k);
    end
    exact_roots(k) = root;
end
zeta = exact_roots(n);
end

function [root, info] = bounded_fzero(fun, bracket, P, identifier)
% No TolX override: base MATLAB's default fzero tolerances apply.
% MaxIter/MaxFunEvals are not fzero options: enforce limits locally.
evaluations = 0;
iterations = 0;
options = optimset('Display', 'off', 'FunValCheck', 'on', 'OutputFcn', @monitor);
try
    [root, ~, flag, info] = fzero(@evaluate, bracket, options);
catch cause
    error(identifier, 'Bracketed fzero on [%.16g, %.16g] failed: %s', bracket(1), bracket(2), cause.message);
end
if flag <= 0 || ~finite_scalar(root)
    error(identifier, 'Bracketed fzero failed: exitflag %d, iterations %d, evaluations %d.', flag, iterations, evaluations);
end
    function value = evaluate(x)
        evaluations = evaluations+1;
        if evaluations > P.TF_rootMaxFunEvals
            error(identifier, 'Exceeded %d root function evaluations.', P.TF_rootMaxFunEvals);
        end
        value = fun(x);
        require_finite(value, 'root function value');
    end
    function stop = monitor(~, ~, state)
        stop = false;
        if strcmp(state, 'iter')
            iterations = iterations+1;
            stop = iterations >= P.TF_rootMaxIter;
        end
    end
end

function varargout = properties(codes, spec1, value1, spec2, value2, fluid)
if nargin < 6
    fluid = 'PARAHYD';
end
varargout = cell(1, nargout);
try
    [varargout{:}] = refpropm(codes, spec1, value1, spec2, value2, fluid);
catch cause
    error('topfill_sources:PropertyState', ...
        'Invalid %s property state: %s at %s=%.16g, %s=%.16g [refpropm units]. %s', ...
        fluid, codes, spec1, value1, spec2, value2, cause.message);
end
for k = 1:numel(varargout)
    if ~finite_scalar(varargout{k})
        error('topfill_sources:PropertyState', ...
            '%s property %s is non-real/non-finite at %s=%.16g, %s=%.16g [refpropm units].', ...
            fluid, codes(k), spec1, value1, spec2, value2);
    end
end
end

function validate_flight_controls(P, mode)
for name = {'TF_seriesExponentLimit', 'TF_shortTimeFo', 'TF_seriesMaxTerms', ...
        'TF_exactBesselRoots', 'TF_rootMaxIter', 'TF_rootMaxFunEvals'}
    is_count = any(strcmp(name{1}, {'TF_seriesMaxTerms', 'TF_exactBesselRoots', 'TF_rootMaxIter', 'TF_rootMaxFunEvals'}));
    require_control(P, name{1}, is_count, false);
end
if ~isfield(P, 'g')
    error('topfill_sources:BadParameter', 'Missing common parameter P.g [m/s^2].');
end
require_finite(P.g, 'P.g');
if P.g < 0
    error('topfill_sources:BadParameter', 'P.g must be nonnegative.');
end
if strcmp(mode, 'spray')
    require_control(P, 'TF_D_d', false, false);
    v = P.TF_velocityBracket;
    if ~isnumeric(v) || ~isreal(v) || numel(v) ~= 2 || any(~isfinite(v)) || v(1) <= 0 || v(2) <= v(1)
        error('topfill_sources:BadParameter', 'TF_velocityBracket must contain two increasing positive finite speeds.');
    end
else
    for name = {'TF_D_0', 'TF_ell_g', 'TF_C_j', 'TF_areaRelTol', 'TF_areaAbsTol'}
        require_control(P, name{1}, false, false);
    end
    require_control(P, 'TF_jetAreaExcessLimit', false, true);
end
end

function require_control(P, name, integer, allow_zero)
if ~isfield(P, name) || ~finite_scalar(P.(name))
    error('topfill_sources:BadParameter', 'P.%s must be a finite real scalar.', name);
end
value = P.(name);
if value < 0 || (~allow_zero && value == 0) || (integer && value ~= fix(value))
    error('topfill_sources:BadParameter', 'Invalid P.%s = %.16g.', name, value);
end
end

function value = text_choice(value, choices, label)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || ~isrow(value) || ~any(strcmp(value, choices))
    error('topfill_sources:BadParameter', '%s must be one of: %s.', label, strjoin(choices, ', '));
end
end

function require_positive_property(value, label)
if ~finite_scalar(value) || value <= 0
    error('topfill_sources:PropertyState', '%s must be real, finite and positive; got %.16g.', label, value);
end
end

function require_finite(value, label)
if ~finite_scalar(value)
    error('topfill_sources:BadInput', '%s must be a real, finite numeric scalar.', label);
end
end

function yes = finite_scalar(value)
yes = isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value);
end

function assert_finite_output(out)
fields = fieldnames(out);
for k = 1:numel(fields)
    value = out.(fields{k});
    if isnumeric(value) && (~isreal(value) || any(~isfinite(value(:))))
        error('topfill_sources:NumericalState', ...
            'Output %s is non-real/non-finite; check input magnitudes and property state.', fields{k});
    end
end
end

function out = empty_output()
names = {'J_top_liq', 'J_top_vap', 'H_top_liq', 'H_top_vap', 'Q_vap_to_top', ...
    'x_flash', 'F', 'M', 'E', 'T_star', 'h_f', 'h_g', 'L_star', ...
    'h_0', 'h_g0', 'h_bar', 'D_d', 'v_t', 'v_guess', 'Re_d', 'C_D', 't_fall', ...
    'Nu', 'Fo', 'f_cond', 'K_l', 'K_v', 'p_crit', 'T_0', 'rho_l', ...
    'mu_l', 'a_l', 'T_film', 'mu_v', 'k_v', 'cp_v', 'Pr_v', 'V_d', ...
    'S_d', 'N_dot', 'N_flight', 'root_iterations', 'h_transfer', ...
    'series_terms', 'series_error_bound', 'Q_raw', 'Q_dry', ...
    'D_0', 'w_0', 'w_H', 'D_H', 'A_j', 'A_geom', 'jet_area_excess', ...
    'max_jet_slope', 'Ra_g', 'beta_v'};
out = struct();
for k = 1:numel(names)
    out.(names{k}) = 0;
end
out.mode = '';
out.ReBasis = '';
out.dryout = false;
out.series_short_time = false;
out.jet_slender_check_assessed = false;
out.warnings = struct('diameter_out_of_range', false, ...
    'Re_above_2e5', false, 'series_not_converged', false, ...
    'jet_slender_geometry_failed', false);
end
