% Custom pump-driven scenario. Edit C primary inputs below.
% Inherits material constants, grids and numerical settings from Case 3.
% Geometry: horizontal cylindrical ST, vertical cylindrical ET, SI units.
Parameters_TrailerToMain_Pump;
C = struct();
C.VTotal1 = 18000*litersTom3;          % [m^3]total volume of (ST)    
C.VTotal2 = 18000*litersTom3;           % [m^3] total volume of (ET)   
C.R1 = 1; 	         				  % [m] radius of (ST)
C.R2 = 1;  				          % [m] radius of (ET)
C.p10 = 3*barToPa;        % [Pa] initial pressure !! VALUE SHOULD BE BELOW PRESSURE RATING OR CRITICAL PRESSURE (186 psia), WHICHEVER IS LOWEST !!
C.TL10 = 21;                 % [K] initial liquid temperature
C.initialfillfraction = 0.9; % [0-1] initial filling fraction
C.p20 = 3*barToPa;             % [Pa] initial pressure !! VALUE SHOULD BE BELOW PRESSURE RATING OR CRITICAL PRESSURE (186 psia), WHICHEVER IS LOWEST !!
C.TL20 = 21;                  % [K] initial liquid temperature
C.Tw20 = 21;                    % [K] initial wall temperature     
C.pct_hL20 = 0.01;              % initial level of liquid, measured in inH2O but reported as a fraction (i.e. 0.5 is 5 out of 10 inH2O). Value should be between >0 and 1 (=0 may trigger errors)
C.Jboil0 = 0;                   % [kg/s] initial boiling flow of vaporizer
C.Jtr0 = 0;                     % [kg/s] initial transmission line flow
C.STBoiloffrate = 0.015/dayTosec;                       % [s^-1] continuous fractional evaporation coefficient; nominal 1.5%/day; isolated daily loss fraction = 1-exp(-0.015).
C.ETBoiloffrate = 0.015/dayTosec;                       % [s^-1] continuous fractional evaporation coefficient; nominal 1.5%/day; isolated daily loss fraction = 1-exp(-0.015).
% mVap0, Tboil, and tau_vap do not specify heater energy or heating power.
% Vaporizer energy storage, heat supply, and return-state consistency remain
% unresolved (LH2-ISSUE-021); parameter values are preserved.
C.mVap0 = 0;                    % [kg] initial liquid mass in vaporizer tubes
C.Tboil = 22;                   % [K] temperature of vapor bubbles
C.tau_vap = 0.3;                % [s] vaporizer time constant !! MAY NEED TO INCREASE THIS VALUE IF ODE SOLVER CRASHES (TOO STIFF) !!
C.c_vap = 4e-4;                 % [m^2] vaporizer valve effective flow area
C.VapValveState = 0;            % initial vaporizer valve state
C.DPipe = 2*inTom;              % [m] diameter of pipe
C.LPipe = 10;                   % [m] transmission line length
C.drPipe = 1e-6;                % roughness of pipe
C.tau_tr = 5;                  % [s] transmission line delay constant !! MAY NEED TO INCREASE THIS VALUE IF ODE SOLVER CRASHES (TOO STIFF) !!
C.dE = 0.4*inTom;		       % [m] transfer line valve diameter (10 in.)
C.kE = 4;				       % [] transfer line valve coefficient
C.S_valve1 = 0.001;              % [m^2] orifice area of ST vent valve !! MAY NEED TO REDUCE THIS VALUE IF ODE SOLVER CRASHES (TOO STIFF) !!
C.STVentState = 0;               % initial ST vent state (starts closed)
C.S_valve2 = 3.1416*(2.5*0.0035)^2; % [m^2] orifice area of ET vent valve !! MAY NEED TO REDUCE THIS VALUE IF ODE SOLVER CRASHES (TOO STIFF) !!
C.ETVentState = 0;               % initial ET vent state (starts closed) 
C.PumpMassTransferFast=30*kgminTokgsec;      % [kg/s] H2 mass transfer being pumped at "Fast" mode
C.PumpMassTransferSlow=15*kgminTokgsec;      % [kg/s] H2 mass transfer being pumped at "Slow" mode
C.PumpHeatCond=30;                           % [W] Estimated conducted Heat Rate at the pump 
C.PumpHeatGain=650;                          % [W/1000kghr] Estimated Heat gain due to pump inefficiencies (mesured @1000 kg/hr flowrate)
C.PumpIsenEff=0.7;
C.p_ST_low = 7*barToPa;        % [Pa] ST vent valve lower pressure threshold (= PRD hysteresis pressure)
C.p_ST_high = 8*barToPa;     % [Pa] ET vent valve upper pressure threshold (= PRD set pressure)
C.p_ST_final = 7*barToPa;      % [Pa] final venting pressure for (ST) (= pressure in the trailer before leaving the station)
C.p_ST_min = 1.2*barToPa;   % [Pa] minimum allowable tank 1 pressure (article sect. 3.2)
C.p_ET_low = 9*barToPa;        % [Pa] ET vent valve lower pressure threshold (= PRD hysteresis pressure)
C.p_ET_high = 10*barToPa;       % [Pa] ET vent valve upper pressure threshold (= PRD set pressure) 
C.p_ET_final = 10*barToPa;      % [Pa] final venting pressure for (ET) (= pressure in the truck's tank before leaving the station)
C.TopET = 0.9;                  % [] maximum fraction full for ET, when fill stops. Value should be between 0 and 1 (0.9 = 90%)
% Empty means derive from the inputs above using the predefined correlations.
C.Tv10 = []; % [K] vapor temperature; empty = pressure-based correlation + 0.1 K.
C.Tv20 = []; % [K] vapor temperature; empty = pressure-based correlation + 0.1 K.
C.QdotEL1 = []; % [W] environmental heat to ST liquid; empty = volume scaling.
C.QdotEV1 = []; % [W] environmental heat to ST vapor; empty = volume scaling.
C.QdotEW2 = []; % [W] environmental heat to ET wall; empty = volume correlation.
C.mw2 = []; % [kg] ET wall mass; empty = scenario-specific volume scaling.
C.tFinal = []; % [s] transfer duration; empty = existing estimate. Stationary stays 3600 s.
LH2Model = initialize_custom_parameters(LH2Model, C, true, HydrogenTransfer);
clear C;
