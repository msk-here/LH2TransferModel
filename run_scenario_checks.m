function run_scenario_checks(baselineDir, duration)
%RUN_SCENARIO_CHECKS Configuration, custom workflow and optional old-code regression.
% run_scenario_checks; or run_scenario_checks('path/to/pre-change/files', 2).
% Baseline must include the user's pre-change parameter files and both hosts.
if nargin < 1, baselineDir = ''; end
if nargin < 2, duration = 2; end
repo = fileparts(mfilename('fullpath'));
oldDir = pwd;
oldPath = path;
cleanup = onCleanup(@() restore_location(oldDir,oldPath));
cd(repo);
addpath(repo);
visibility = get(groot,'defaultFigureVisible');
set(groot,'defaultFigureVisible','off');
figureCleanup = onCleanup(@() set(groot,'defaultFigureVisible',visibility));
for value = {-0.1, 1.1, NaN, Inf, [0 1], [], 1i, '0', true}
    must_fail(@() validate_fill_configuration(value{1}, 'spray'), 'LH2:InvalidTopBottomRatio');
end
must_fail(@() validate_fill_configuration(0.3, 'invalid'), 'LH2:InvalidTopfillMode');
assert(~validate_fill_configuration(0, 'ignored'));
for r = [0.3 1]
    assert(validate_fill_configuration(r,'spray') && validate_fill_configuration(r,'jet'));
end
for c = [0 9 NaN]
    try
        scenario_metadata(c);
        error('test:ExpectedError','Unsupported case was accepted.');
    catch cause
        assert(~strcmp(cause.identifier,'test:ExpectedError'));
    end
end
fprintf('PASS input validation and unsupported-case rejection\n');
for c = 1:8
    info = scenario_metadata(c);
    assert(info.isPump == any(c == [3 5 6 8]));
    P = initialize(c,0,'spray',1);
    Q = initialize(c,0,'ignored',1);
    assert(isequaln(P,Q)); % Mode is applied only after parameter scripts.
    if c <= 6 && ~isempty(baselineDir)
        cd(baselineDir);
        assignin('base','Topfill',0); % Historical interface, baseline only.
        oldP = initialize(c,0,'spray',1);
        cd(repo);
        assert(isequaln(P,oldP), 'Case %d parameters differ from baseline.', c);
        oldP.TF_r = 0; oldP.TF_mode = 'spray'; oldP.tFinal = duration;
        cd(baselineDir);
        oldData = simulate(oldP,info.isPump,1);
        cd(repo);
        P.TF_r = 0; P.TF_mode = 'ignored'; P.tFinal = duration;
        newData = simulate(P,info.isPump,1);
        compare_bits(oldData,newData);
        fprintf('PASS Case %d baseline parameters and bitwise histories (%g s)\n',c,duration);
    else
        fprintf('PASS Case %d configuration and solver routing\n',c);
    end
end
for c = [7 8]
    info = scenario_metadata(c);
    P = initialize(c,0,'spray',1);
    P.Jtr0 = 0.1; % Exercise nonzero top sources before pressure-control startup.
    Q = initialize_custom_parameters(P, struct('VTotal2',P.VTotal2*0.8, ...
        'R2',P.R2*0.9,'p20',P.p20*0.9,'DPipe',P.DPipe*0.9), info.isPump,1);
    assert(Q.H == Q.VTotal2/Q.A2 && Q.VL20 == Q.hL20*Q.A2);
    assert(Q.mv20 ~= P.mv20 && Q.f ~= P.f && Q.Tv20 ~= P.Tv20);
    P.TF_r=0; P.TF_mode='ignored'; P.tFinal=duration;
    bottom=simulate(P,info.isPump,1);
    Q.TF_r=0; Q.TF_mode='ignored'; Q.tFinal=duration;
    changed=simulate(Q,info.isPump,1);
    assert(~isequal(bottom.mL2,changed.mL2), 'Custom input had no state-history effect.');
    for r = [1 0.3]
        for mode = {'spray','jet'}
            P.TF_r=r; P.TF_mode=mode{1};
            data=simulate(P,info.isPump,1);
            assert(data.t(end)==duration && any(data.Jtr>0));
            assert(any(data.QdotTopfill~=0), 'Top source heat was not exercised.');
            fprintf('PASS Case %d r=%g %s (%g s)\n',c,r,mode{1},duration);
        end
    end
    stationary=initialize(c,0,'spray',0);
    assert(stationary.tFinal==3600);
    stationary.tFinal=duration; stationary.TF_r=0; stationary.TF_mode='ignored';
    a=simulate(stationary,info.isPump,0);
    stationary.TF_r=1; stationary.TF_mode='jet';
    b=simulate(stationary,info.isPump,0);
    assert(all(a.Jtr==0) && all(b.Jtr==0));
    P = Parameters_topfill_defaults(P);
    P.caseNumber=c; P.description=info.Scenario; P.transferMethod=info.Method;
    % Exercise the existing extraction, plotting, saving and both export paths.
    assignin('base','Case',c);
    assignin('base','LH2Model',P);
    assignin('base','Simulation',data);
    evalin('base','Data_extraction;');
    extracted=evalin('base','Simulation');
    plotLH2Data(extracted,0,"");
    % A stationary/short run may have no mass denominator for relative venting.
    zeroTransfer=extracted;
    for field={'EffectiveTransfMass','UsedMass','Boiloff_ST','Boiloff_ET'}
        zeroTransfer.(field{1})(:)=0;
    end
    plotLH2Data(zeroTransfer,0,"");
    output=string(tempname); mkdir(output); output=output+filesep;
    SaveResultsFunction(P,extracted,output,"test");
    CreateXLSTXT(P,extracted,output,"test",c);
    UpdateXLSLog(P,extracted,output,"logtest",c);
    assert(~isfile(output+"ResultsLog.xlsx"));
    fprintf('PASS Case %d changed-input, stationary and post-processing checks; artifacts: %s\n',c,output);
end
fprintf('PASS scenario checks completed; baseline comparison executed=%d\n',~isempty(baselineDir));
end

function P=initialize(c,r,mode,transfer)
info=scenario_metadata(c);
assignin('base','TopBottomRatio',r);
assignin('base','TopfillMode',mode);
assignin('base','HydrogenTransfer',transfer);
assignin('base','LH2Model',struct('name',info.name+"_Test"));
evalin('base',char(info.parameterFile));
P=evalin('base','LH2Model');
end

function data=simulate(P,isPump,transfer)
evalin('base','clear global ETTVentState ET_fill_complete ST_ready ST_vent_complete ET_vent_complete Process_complete');
assignin('base','LH2Model',P);
assignin('base','odesolver',1);
assignin('base','HydrogenTransfer',transfer);
if isPump
    captured=evalc('data=LH2Simulate_Pump;'); %#ok<NASGU>
else
    captured=evalc('data=LH2Simulate;'); %#ok<NASGU>
end
assert(data.t(end)==P.tFinal,'Simulation did not reach requested duration.');
fields=fieldnames(data);
for k=1:numel(fields)
    v=data.(fields{k});
    if isnumeric(v), assert(all(isfinite(v(:))), 'Nonfinite saved state.'); end
end
end

function compare_bits(a,b)
assert(isequal(fieldnames(a),fieldnames(b)));
fields=fieldnames(a);
for k=1:numel(fields)
    x=a.(fields{k}); y=b.(fields{k});
    if isa(x,'double')
        assert(isequal(size(x),size(y)) && ...
            isequal(typecast(x(:),'uint64'),typecast(y(:),'uint64')), ...
            'Baseline bit mismatch in %s.',fields{k});
    else
        assert(isequaln(x,y), 'Baseline metadata mismatch in %s.',fields{k});
    end
end
end

function must_fail(f,id)
try
    f();
catch cause
    assert(strcmp(cause.identifier,id), 'Unexpected error: %s',cause.message);
    return;
end
error('test:ExpectedError','Expected %s.',id);
end

function restore_location(folder,oldPath)
cd(folder);
path(oldPath);
end
