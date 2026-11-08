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

Case=3;     % '1' for running original case and parameters,
            % '2' for running trailer to main tank by pressure difference
            % '3' for running trailer to main tank by transfer pump
            % '4' for running main tank to on-board tank by pressure increment
            % '5' for running main tank to on-board tank by transfer pump
            % '6' for running external tank blowdown
            % '7' custom pressure-driven (Parameters_Custom_PressDiff.m)
            % '8' custom pump-driven (Parameters_Custom_Pump.m)

HydrogenTransfer=1; % '0' for simulating stationary process. Simulation time of 1h.
                    % '1' for simulating transfer process. Simulation time of transfer process duration.

% [] selects legacy behavior. To opt in, supply an explicit configuration
% documented in LH2UniformCompletionConfig and the Gate 2 report.
UniformCompletion = [];

TopBottomRatio=0; % Top inlet fraction: 0 bottom, 0<r<1 hybrid, 1 top.
TopfillMode='spray'; % 'spray' or 'jet'; used only for TopBottomRatio > 0.
            
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

validate_fill_configuration(TopBottomRatio, TopfillMode);
scenario = scenario_metadata(Case); % Reject unsupported cases explicitly.
disp("Running " + scenario.Scenario + " (" + scenario.Method + ").")
LH2Model.name = scenario.name;
if HydrogenTransfer==0
    LH2Model.name = LH2Model.name + "_Stationary";
else
    LH2Model.name = LH2Model.name + "_Transfer";
end
eval(char(scenario.parameterFile));
LH2Model.caseNumber = Case;
LH2Model.description = scenario.Scenario;
LH2Model.transferMethod = scenario.Method;
LH2Model.TF_mode = TopfillMode;
LH2Model.TF_r = TopBottomRatio;
LH2Model = Parameters_topfill_defaults(LH2Model);
if ~isempty(UniformCompletion)
    LH2Model.UniformCompletion = UniformCompletion;
    LH2UniformCompletionConfig(LH2Model,scenario.isPump);
end

% 2. Run simulation
if scenario.isPump
    Simulation= LH2Simulate_Pump;
else
    Simulation= LH2Simulate;
end

if isfield(Simulation,'UniformCompletion')
    % Raw port evidence and the accepted status own this operating endpoint.
    disp(Simulation.UniformCompletion.status);
    if SaveResults==1
        SaveResultsFunction(LH2Model,Simulation,ResultsPath,dateandtime);
    end
    return
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
    UpdateXLSLog(LH2Model,Simulation,LogPath,dateandtime,Case);
end
toc;

% 8. Computer shutdown if option is activaded

if PCShutdown==1
    system('shutdown -s');
end