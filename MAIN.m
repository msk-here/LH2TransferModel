%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% LH2 TRANSFER MODEL %%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
% Script use to run the LH2 simulation code
% here : (ST) or 1 is trailer (horizontal cylinder)
%        (ET) or 2 is station storage (vertical cylinder)   
clc
close all
clear all  
tic;
dateandtime=string(datetime('now','Format','MMddyy''-''HHmm'));

%% OPTIONS

Case=5;     % '1' for running original case and parameters,
            % '2' for running trailer to main tank by pressure difference
            % '3' for running trailer to main tank by transfer pump
            % '4' for running main tank to on-board tank by pressure increment
            % '5' for running main tank to on-board tank by transfer pump
            % '6' for running external tank blowdown

HydrogenTransfer=1; % '0' for simulating stationary process. Simulation time of 1h.
                    % '1' for simulating transfer process. Simulation time of transfer process duration.

Topfill=0;  % '0' for simulating a bottom fill process.
            % '1' for simulating spray or jet top fill, including hybrid fill.
TopfillMode='spray'; % 'spray' or 'jet'; used only when Topfill = 1.
TopBottomRatio=0;    % Fraction r of total flow through the top inlet, in [0, 1].
                    % r = 1: pure top fill; 0 < r < 1: hybrid; r = 0: bottom fill.
            
odesolver= 1;   % '1' for using ode45. More accurate, more computing time. Might crash if system is stiff. 
                % '2' for using ode15s. For stiff systems.

SavePlots=0;    % '0' for not saving plots.
                % '1' for saving plots as .png.
                PlotsPath="results\"; % final slash required

SaveResults=0;  % '0' for not saving workspace.
                % '1' for saving "LH2Model" and "Simulation" variables.
                ResultsPath="results\"; % final slash required

WriteXlsTxt=0;  % '0' for not writing main results at .cvs and .txt file.
                % '1' for creating a .xls and .txt file with main results.
                XlsTxtPath="results\"; % final slash required

UpdateLog=0;    % '0' for not writing main results to log file.
                % '1' for updating .xls log file with main results.
                LogPath="results\"; % final slash required

PCShutdown=0;   % '1' for shutting down the computer once the simulation and data extraction has finished.
              


%% CALLING CODE FUNCTIONS
 
% 1. initialize parameters

if Case==2
    disp('Running Trailer to Main tank model by pressure gradient.')
    LH2Model.name="TrailerToMainPressureDiff";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end

    Parameters_TrailerToMain_PressDiff;

elseif Case==3
    disp('Running Trailer to Main tank model by transfer pump.')
    LH2Model.name="TrailerToMainPump";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end
    
    % Parameters_TrailerToMain_Pump;
    Parameters_TrailerToMain_Pump

elseif Case==4
    disp('Running Main tank to On-board tank model by pressure gradient.')
    LH2Model.name="MainToOnboardPressureDiff";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end
    
    Parameters_MainToOnboard_PressDiff;

elseif Case==5
    disp('Running Main tank to On-board tank model by transfer pump.')
    LH2Model.name="MainToOnboardPump";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end
    
    Parameters_MainToOnboard_Pump;

elseif Case==6
    disp('Running External tank initial blowdown')
    LH2Model.name="ExternalTankInitialBlowdown";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end
    
    Parameters_TrailerToMain_Pump_InitialBlowdown_PlugPower;

else
    disp('Running original parameters and scenario (Trailer to Main tank)')
    LH2Model.name="Original-TrailerToMain";
    if HydrogenTransfer==0
        LH2Model.name=LH2Model.name+"_Stationary";
    else
        LH2Model.name=LH2Model.name+"_Transfer";
    end
    
    Parameters_Original;

end

LH2Model.TF_enabled = (Topfill == 1);
LH2Model.TF_mode = TopfillMode;
LH2Model.TF_r = TopBottomRatio;
LH2Model = Parameters_topfill_defaults(LH2Model);

% 2. Run simulation
if Case==3 || Case==5 || Case ==6
    Simulation= LH2Simulate_Pump;
else
    Simulation= LH2Simulate;
end

% 3. Extract data
disp('Now extracting data');
Data_extraction;

% 4. Plot results and save plots
if SavePlots==1
    mkdir ([(char(PlotsPath)) char(dateandtime+"_"+LH2Model.namedetail)])
end
PlotsPathSubfolder=PlotsPath+dateandtime+"_"+LH2Model.namedetail+"\";
plotLH2Data(Simulation,SavePlots,PlotsPathSubfolder);

% 5. Save results
if SaveResults==1
    SaveResultsFunction(LH2Model,Simulation,ResultsPath,dateandtime);
end

% 6. Create .txt and .xls files with main results
if WriteXlsTxt==1
    mkdir ([(char(XlsTxtPath)) char(dateandtime+"_"+LH2Model.namedetail)])
    XlsTxtPathSubfolder=XlsTxtPath+dateandtime+"_"+LH2Model.namedetail+"\";
    CreateXLSTXT(LH2Model,Simulation,XlsTxtPathSubfolder,dateandtime,Case);
end

% 7. Update .xls log file with main results
if UpdateLog==1
    UpdateXLSLog(LH2Model,Simulation,LogPath,dateandtime,Case,Topfill);
end
toc;

% 8. Computer shutdown if option is activaded

if PCShutdown==1
    system('shutdown -s');
end