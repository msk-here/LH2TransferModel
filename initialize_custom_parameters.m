function P = initialize_custom_parameters(P, C, isPump, HydrogenTransfer)
%INITIALIZE_CUSTOM_PARAMETERS Apply primary inputs, then rebuild dependencies.
% C contains primary inputs only. Empty optional values retain derived defaults.
% The ST fill fraction retains the legacy total-mass estimate convention.
psiToPa = 6894.75729;
barToPa = 100000;
kgminTokgsec = 1/60;
fields = fieldnames(C);
derived = {'A1','A2','Lcyl','H','totalmass10','Ts10','Ts20','rhov10','rhoL10', ...
    'Vullage10','mL10','mv10','hL20','VL20','rhoL20','mL20','rhov20','mv20','f', ...
    'TF_r','TF_mode','TF_enabled','TF_ell_g'};
for k = 1:numel(fields)
    key = fields{k};
    if any(strcmp(key,derived))
        error('LH2:DerivedCustomParameter', ...
            '%s is derived or configured in MAIN; edit primary custom inputs instead.',key);
    end
    if ~isfield(P,key) && ~any(strcmp(key, {'Tv10','Tv20'}))
        error('LH2:UnknownCustomParameter', 'Unknown custom parameter %s.', key);
    end
    if ~isempty(C.(key))
        validateattributes(C.(key), {'numeric'}, {'real','finite','scalar'}, mfilename, key);
        P.(key) = C.(key);
    end
end
for key = {'VTotal1','VTotal2','R1','R2','p10','p20','TL10','TL20','Tw20', ...
        'DPipe','LPipe','drPipe','dE','tau_tr','tau_vap'}
    validateattributes(P.(key{1}), {'numeric'}, {'positive','finite','real','scalar'}, mfilename, key{1});
end
assert(P.initialfillfraction > 0 && P.initialfillfraction < 1 && ...
    P.pct_hL20 > 0 && P.pct_hL20 < P.TopET && P.TopET < 1, ...
    'LH2:InvalidCustomFill', 'Require 0<initialfillfraction<1 and 0<pct_hL20<TopET<1.');
assert(P.p_ET_low <= P.p_ET_high, 'LH2:InvalidCustomPressure', 'ET low threshold must not exceed high threshold.');
if isPump
    assert(P.PumpMassTransferFast > 0 && P.PumpMassTransferSlow > 0 && ...
        P.PumpMassTransferSlow <= P.PumpMassTransferFast && ...
        P.PumpIsenEff > 0 && P.PumpIsenEff <= 1 && P.p_ST_low <= P.p_ST_high, ...
        'LH2:InvalidCustomPump', 'Require positive slow<=fast flow, 0<efficiency<=1 and ST low<=high.');
end
% Preserve the predefined correlations and operation ordering.
P.A1 = pi*(P.R1)^2;	          % [m^2] cross section area of (ST)
P.A2 = pi*(P.R2)^2;	          % [m^2] cross section area of (ET)
P.Lcyl = P.VTotal1/P.A1; % [m] length of (ST)
P.H = P.VTotal2 /P.A2;   % [m] height of (ET)
P.totalmass10 = P.initialfillfraction*P.VTotal1*P.rho_L;        % [kg] inital total mass (liquid + vapor) !! using density that considers only liquid, but this is only an estimate value for total mass.
if ~isfield(C, 'Tv10') || isempty(C.Tv10)
    P.Tv10 = 0.1+(-1.603941638811E-11*(P.p10/psiToPa)^6 + 7.830478134841E-09*(P.p10/psiToPa)^5 - 1.549372675881E-06*(P.p10/psiToPa)^4 + 1.614567978153E-04*(P.p10/psiToPa)^3 - 9.861776990784E-03*(P.p10/psiToPa)^2 + 4.314905904166E-01*(P.p10/psiToPa)^1 + 1.559843335080E+01); % saturation temperature of vapor, from Refprop
end
P.Ts10 = P.T_c*(P.p10/P.p_c)^(1/P.lambda);      % [K] initial film temperature. From Osipov 2008, see ref in Readme file
P.rhov10 = refpropm('D','T',P.Tv10,'P',P.p10/1000,'PARAHYD'); % [g/L] initial density of the vapor phase in ST
P.rhoL10 = refpropm('D','T',P.TL10,'Q',0,'PARAHYD');                 % [g/L] inital density of liquid phase in ST
P.Vullage10 = (P.totalmass10- P.rhoL10*P.VTotal1)/(P.rhov10-P.rhoL10); % [m^3] initial ullage volume in ST
P.mL10 = P.rhoL10 * (P.VTotal1 - P.Vullage10);         % [kg] initial liquid mass in ST
P.mv10 = P.totalmass10 - P.mL10;                              % [kg] initial vapor mass in ST
if ~isfield(C, 'Tv20') || isempty(C.Tv20)
    P.Tv20 = 0.1+(-1.603941638811E-11*(P.p20/psiToPa)^6 + 7.830478134841E-09*(P.p20/psiToPa)^5 - 1.549372675881E-06*(P.p20/psiToPa)^4 + 1.614567978153E-04*(P.p20/psiToPa)^3 - 9.861776990784E-03*(P.p20/psiToPa)^2 + 4.314905904166E-01*(P.p20/psiToPa)^1 + 1.559843335080E+01); % saturation temperature of vapor, from Refprop
end
P.Ts20 = P.T_c*(P.p20/P.p_c)^(1/P.lambda);      % [K] initial film temperature.  From Osipov 2008, see reference in Readme file
P.hL20 = P.pct_hL20 * P.H;                                    % [m] initial level of liquid in ET
P.VL20 = P.hL20 * P.A2;                                       % [m^3] inital volume of liquid in ET
P.rhoL20 = refpropm('D','T',P.TL20,'Q',0,'PARAHYD');                 % [g/L] inital density of liquid phase in ET
P.mL20 = P.rhoL20 *P.VL20;                                    % [kg] initial mass of liquid in ET
P.rhov20 = refpropm('D','T',P.Tv20,'P',P.p20/1000,'PARAHYD'); % [g/L] initial density of the vapor phase in ET
P.mv20 = P.rhov20 * (P.VTotal2 - P.VL20);              % [kg] initial mass of vapor in ET
if isfield(P,'TF_ell_g')
    P.TF_ell_g = (P.VTotal2-P.VL20)/P.A2;
end
if ~isfield(C, 'QdotEL1') || isempty(C.QdotEL1)
    P.QdotEL1 = 200*(P.VTotal1/64.5);                % [W] heat transfer from environment to liquid. Using initial value as a reference, scaled to actual volume.
end
if ~isfield(C, 'QdotEV1') || isempty(C.QdotEV1)
    P.QdotEV1 = 40*(P.VTotal1/64.5);                 % [W] heat transfer from environment to vapor. Using initial value as a reference, scaled to actual volume.
end
if ~isfield(C, 'QdotEW2') || isempty(C.QdotEW2)
    P.QdotEW2 = -7.462776654302E-02*P.VTotal2^2 + 4.445867251697E+00*P.VTotal2 + 3.108170556297E+01;  % [W] heat transfer from environment to vessel's wall depending on the volume. Correlation from LLNL.
end
if ~isfield(C, 'mw2') || isempty(C.mw2)
    P.mw2 = P.VTotal2*5000/12.5;       % [kg] mass of ET inner vessel. Using as a reference: tank of 12500L weights 5000kg
    if isPump, P.mw2 = P.mw2/2; end % Existing pump wall-mass convention.
end
P.f = 1.3/log(P.DPipe/2/P.drPipe)^2; % friction parameter
assert(P.Vullage10 > 0 && P.Vullage10 < P.VTotal1 && P.mL10 > 0 && P.mv10 > 0, ...
    'LH2:InvalidCustomInventory', 'ST fill/temperature combination must leave positive liquid and vapor inventories.');
if HydrogenTransfer==0
    P.tFinal = 3600; % Existing stationary-process duration semantics.
elseif ~isfield(C, 'tFinal') || isempty(C.tFinal)
    if isPump
        P.tFinal = .7*60*60*(P.VTotal2/12.5)*(P.TopET-P.pct_hL20)*(30*kgminTokgsec/P.PumpMassTransferFast);
    else
        P.tFinal = 0.7*0.75*0.75*60*60*(P.VTotal2/12.5)*(P.TopET-P.pct_hL20)/1.25;
    end
end
validateattributes(P.tFinal, {'numeric'}, {'positive','finite','real','scalar'}, mfilename, 'tFinal');
P.namedetail = P.name+"_"+string(P.VTotal1)+"-"+string(P.VTotal2)+"m3_"+ ...
    string(P.p10/barToPa)+"-"+string(P.p20/barToPa)+"barInitial";
end
