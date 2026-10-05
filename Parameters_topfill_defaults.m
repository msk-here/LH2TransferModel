function P = Parameters_topfill_defaults(P)
%PARAMETERS_TOPFILL_DEFAULTS Revision 3, Section 7 parameter register.
% Existing fields are never overwritten. All new defaults are populated.
% Numerical choices below implement the user's completion decisions.
% This function reads only common geometry and optional ETinletdiameter.

if ~isstruct(P) || ~isscalar(P)
    error('Parameters_topfill_defaults:BadParameters', ...
        'P must be a scalar LH2Model parameter struct.');
end

P = add_default(P, 'TF_enabled', false); % [-] Section 7: user; assumed disabled.
P = add_default(P, 'TF_mode', 'spray'); % [-] Section 7: assumed initial mode.
P = add_default(P, 'TF_r', 0); % [-] Eq. (47); assumed baseline-preserving split.
P = add_default(P, 'TF_D_d', 0.006); % [m] P10 Table 6, p. 28: reference diameter.
P = add_default(P, 'TF_ReBasis', 'tenDamme'); % [-] Eq. (27); P10 Fig. 12 review.

if ~isfield(P, 'TF_D_0')
    if isfield(P, 'ETinletdiameter')
        P.TF_D_0 = P.ETinletdiameter; % [m] Section 7: repo legacy value, assumed.
    else
        P.TF_D_0 = 0.02; % [m] Section 7: repo legacy value, assumed.
    end
end
if ~isfield(P, 'TF_ell_g')
    names = {'VTotal2', 'VL20', 'A2'};
    for k = 1:numel(names)
        if ~isfield(P, names{k}) || ~finite_scalar(P.(names{k}))
            error('Parameters_topfill_defaults:MissingGeometry', ...
                'Finite scalar P.%s is needed to default TF_ell_g.', names{k});
        end
    end
    if P.A2 <= 0 || P.VTotal2 <= P.VL20 || P.VL20 < 0
        error('Parameters_topfill_defaults:BadGeometry', ...
            'Default TF_ell_g requires A2 > 0 and VTotal2 > VL20 >= 0.');
    end
    P.TF_ell_g = (P.VTotal2-P.VL20)/P.A2; % [m] Eq. (1), Section 7: assumed initial geometric reference, fixed for the run.
end
P = add_default(P, 'TF_C_j', 1); % [-] Eq. (44), Section 7: assumed uncalibrated screening scale.

% Section 7 numerical controls; populated by the user's completion decisions.
P = add_default(P, 'TF_heightTiny', 1e-9); % [m] Section 4.4; assumed numerical setting.
P = add_default(P, 'TF_seriesExponentLimit', 50); % [-] Eqs. (34), (46); assumed numerical setting.
P = add_default(P, 'TF_shortTimeFo', 1e-6); % [-] Eqs. (34), (46) numerical evaluation; assumed numerical setting.
P = add_default(P, 'TF_exactBesselRoots', 20); % [count] Eq. (46); assumed numerical setting.
P = add_default(P, 'TF_seriesMaxTerms', 4096); % [count] Section 7; assumed numerical setting (covers the 1e-6 full-series endpoint).
P = add_default(P, 'TF_velocityBracket', [1e-6, 50]); % [m/s] Eq. (27a); assumed numerical setting; fzero keeps default tolerances.
P = add_default(P, 'TF_rootMaxIter', 256); % [count] Section 7; assumed numerical setting; enforced by OutputFcn.
P = add_default(P, 'TF_rootMaxFunEvals', 1024); % [count] Section 7; assumed numerical setting; enforced by a local evaluation counter.
P = add_default(P, 'TF_areaRelTol', 1e-10); % [-] Eq. (42) integral; assumed numerical setting.
P = add_default(P, 'TF_areaAbsTol', 1e-14); % [m^2] Eq. (42) integral; assumed numerical setting.
P = add_default(P, 'TF_jetAreaExcessLimit', 0.01); % [-] Eq. (42), Section 5.2; assumed diagnostic cutoff.
P = add_default(P, 'TF_J_scale', 1e-9); % [kg/s] Eq. (52); assumed numerical setting.
P = add_default(P, 'TF_H_scale', 1e-3); % [W] Eq. (52); assumed numerical setting.
P = add_default(P, 'TF_testMassTol', 1e-12); % [-] Eq. (52) acceptance; assumed numerical setting.
P = add_default(P, 'TF_testEnergyTol', 1e-10); % [-] Eq. (52) acceptance; assumed numerical setting.
P = add_default(P, 'TF_testFig12Tol', 0.03); % [-] Section 8 acceptance; assumed numerical setting.
% Retired controls: TF_seriesTol, TF_velocityTol, TF_bracketMaxIter,
% TF_jetSlopeLimit. Exponent cutoff, default fzero tolerances, a fixed
% bracket, and relative exact-area excess replace those mechanisms.
end

function P = add_default(P, name, value)
if ~isfield(P, name)
    P.(name) = value;
end
end

function yes = finite_scalar(value)
yes = isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value);
end
