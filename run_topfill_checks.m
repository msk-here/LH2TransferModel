%RUN_TOPFILL_CHECKS Milestone C: module tests and 120 s host checks.
% Run from the repo root: run_topfill_checks
% This script runs 20 simulations; it does not call MAIN, extract, plot or save.
odesolver = 1; % 1 = ode45; 2 = ode15s. The same solver is used for every run.

[topfill_checks_results, topfill_checks_status] = run_checks(odesolver);

function [results, status] = run_checks(solver)
assert(isnumeric(solver) && isreal(solver) && isscalar(solver) && ...
    any(solver == [1, 2]), 'odesolver must be 1 (ode45) or 2 (ode15s).');
repo_root = fileparts(mfilename('fullpath'));
old_path = path;
path_cleanup = onCleanup(@() path(old_path));
addpath(repo_root);
t_final = 120;
suite_timer = tic;
results = struct('name', {}, 'passed', {}, 'numbers', {});

% Capture module output so the hosts' clc cannot erase its final report.
module_text = '';
topfill_test_results = struct('passed', {});
topfill_test_status = 'FAIL';
module_timer = tic;
try
    module_text = evalc('test_topfill_sources;');
    module_passes = nnz([topfill_test_results.passed]);
    module_total = numel(topfill_test_results);
    module_ok = strcmp(topfill_test_status, 'PASS') && module_total > 0 && ...
        module_passes == module_total;
    module_numbers = sprintf('PASS=%d FAIL=%d TOTAL=%d runtime=%.3f s', ...
        module_passes, module_total-module_passes, module_total, toc(module_timer));
catch cause
    module_passes = 0;
    module_total = 0;
    module_ok = false;
    module_numbers = sprintf('PASS=0 TOTAL=0 runtime=%.3f s error=%s', ...
        toc(module_timer), error_text(cause));
end
results(end+1) = record('C1 test_topfill_sources', module_ok, module_numbers);

completed_runs = 0;
for case_number = 1:6
    fprintf('Running C2 Case %d: bottom fill and top enabled with r=0.\n', case_number);
    bottom = run_case(case_number, 0, 'spray', 0, solver, t_final);
    zero_split = run_case(case_number, 1, 'spray', 0, solver, t_final);
    completed_runs = completed_runs+bottom.completed+zero_split.completed;
    if bottom.completed && zero_split.completed
        [identical, difference_count, max_state_difference, max_time_difference] = ...
            compare_histories(bottom, zero_split);
        numbers = sprintf(['solver=%d completed=2/2 samples=%d/%d states=%d ' ...
            'bit_differences=%g max_abs_state_difference=%.16g ' ...
            'max_abs_time_difference=%.16g s runtime=%.3f/%.3f s'], ...
            solver, numel(bottom.data.t), numel(zero_split.data.t), ...
            size(bottom.history, 2), difference_count, max_state_difference, ...
            max_time_difference, bottom.runtime, zero_split.runtime);
    else
        identical = false;
        numbers = sprintf(['solver=%d completed=%d/2 t_end=%.16g/%.16g s ' ...
            'runtime=%.3f/%.3f s bottom_error=%s zero_split_error=%s'], ...
            solver, bottom.completed+zero_split.completed, bottom.t_end, ...
            zero_split.t_end, bottom.runtime, zero_split.runtime, ...
            bottom.error, zero_split.error);
    end
    results(end+1) = record(sprintf('C2 Case %d exact regression', case_number), ...
        identical, numbers); %#ok<AGROW>
end

clear bottom zero_split; % Release regression histories before the active runs.
modes = {'spray', 'jet', 'spray', 'jet'};
ratios = [1, 1, 0.3, 0.3];
for case_number = [5, 4]
    for configuration = 1:4
        mode = modes{configuration};
        ratio = ratios(configuration);
        fprintf('Running C3 Case %d: %s r=%.3g.\n', case_number, mode, ratio);
        run = run_case(case_number, 1, mode, ratio, solver, t_final);
        completed_runs = completed_runs+run.completed;
        delta_mass = NaN;
        integrated_flow = NaN;
        residual = NaN;
        mass_evaluated = false;
        if run.completed
            inventory = run.data.mL2+run.data.mv2;
            delta_mass = inventory(end)-inventory(1);
            % Jtr is the actual flow state; Jvvalve2 is a filtered diagnostic.
            % Equal-time event samples contribute zero intervals to trapz.
            integrated_flow = trapz(run.data.t, run.data.Jtr-run.data.Jvvalve2);
            residual = delta_mass-integrated_flow;
            mass_evaluated = all(isfinite([delta_mass, integrated_flow, residual]));
        end
        numbers = sprintf(['solver=%d r=%.3g completed=%d t_end=%.16g s ' ...
            'runtime=%.3f s samples=%d delta_mass=%.16g kg ' ...
            'integral(Jtr-Jvvalve2)=%.16g kg mass_residual=%.16g kg ' ...
            '(Jtr: ODE state; Jvvalve2: first-order filtered diagnostic; ' ...
            'residual reported without an acceptance tolerance)'], ...
            solver, ratio, run.completed, run.t_end, run.runtime, ...
            run.samples, delta_mass, integrated_flow, residual);
        if ~run.completed
            numbers = sprintf('%s error=%s', numbers, run.error);
        end
        results(end+1) = record(sprintf('C3 Case %d %s', case_number, mode), ...
            run.completed && mass_evaluated, numbers); %#ok<AGROW>
    end
end

% Replay every result after all hosts return, including the numeric module log.
fprintf('\nTop-fill checks: solver=%d, tFinal=%g s for every simulation.\n', solver, t_final);
fprintf('C2 requires identical time grids and every saved state bit pattern.\n');
fprintf(['C3 PASS means completion to 120 s, finite states and a finite mass ' ...
    'residual calculation; the reported residual has no assumed tolerance.\n']);
if ~isempty(module_text)
    fprintf('%s', module_text);
    if module_text(end) ~= newline, fprintf('\n'); end
end
for k = 1:numel(results)
    fprintf('%s | %s | %s\n', pass_fail(results(k).passed), ...
        results(k).name, results(k).numbers);
end
passes = nnz([results.passed]);
failures = numel(results)-passes;
status = pass_fail(failures == 0);
fprintf(['SUMMARY: %s | solver=%d tFinal=%g s CHECKS_PASS=%d CHECKS_FAIL=%d ' ...
    'TOTAL=%d MODULE_PASS=%d/%d RUNS_COMPLETED=%d/20 runtime=%.3f s\n'], ...
    status, solver, t_final, passes, failures, numel(results), ...
    module_passes, module_total, completed_runs, toc(suite_timer));
end

function run = run_case(case_number, topfill, mode, ratio, solver, t_final)
run = struct('completed', false, 'runtime', 0, 'samples', 0, ...
    't_end', NaN, 'error', 'none', 'data', struct(), 'history', [], 'fields', {{}});
reset_globals();
waitbars_before = model_waitbars();
run_cleanup = onCleanup(@() cleanup_run(waitbars_before));
run_timer = tic;
try
    parameter_files = {'Parameters_Original', 'Parameters_TrailerToMain_PressDiff', ...
        'Parameters_TrailerToMain_Pump', 'Parameters_MainToOnboard_PressDiff', ...
        'Parameters_MainToOnboard_Pump', ...
        'Parameters_TrailerToMain_Pump_InitialBlowdown_PlugPower'};
    case_names = {'Original-TrailerToMain_Transfer', 'TrailerToMainPressureDiff_Transfer', ...
        'TrailerToMainPump_Transfer', 'MainToOnboardPressureDiff_Transfer', ...
        'MainToOnboardPump_Transfer', 'ExternalTankInitialBlowdown_Transfer'};
    assignin('base', 'Case', case_number);
    assignin('base', 'odesolver', solver);
    assignin('base', 'HydrogenTransfer', 1);
    assignin('base', 'Topfill', topfill);
    assignin('base', 'LH2Model', struct('name', string(case_names{case_number})));
    % The parameter scripts also read base variables and clear LH2Model.
    evalin('base', parameter_files{case_number});
    P = evalin('base', 'LH2Model');
    P.tFinal = t_final; % Override the scenario duration AFTER initialization.
    P.TF_enabled = (topfill == 1);
    P.TF_mode = mode;
    P.TF_r = ratio;
    P = Parameters_topfill_defaults(P);
    assignin('base', 'LH2Model', P);

    % Suppress per-RHS display output without modifying either host function.
    if any(case_number == [3, 5, 6])
        console_text = evalc('run.data = LH2Simulate_Pump;'); %#ok<NASGU>
        expected_columns = P.nL1+P.nV1+P.nL2+P.nV2+52;
    else
        console_text = evalc('run.data = LH2Simulate;'); %#ok<NASGU>
        expected_columns = P.nL1+P.nV1+P.nL2+P.nV2+48;
    end
    run.runtime = toc(run_timer); % Wall time includes parameter initialization.
    assert(isfield(run.data, 't') && isnumeric(run.data.t) && ...
        isreal(run.data.t) && iscolumn(run.data.t) && numel(run.data.t) >= 2 && ...
        all(isfinite(run.data.t)), 'Invalid simulation time history.');
    run.samples = numel(run.data.t);
    run.t_end = run.data.t(end);
    assert(run.data.t(1) == 0 && all(diff(run.data.t) >= 0) && ...
        run.t_end == t_final, 'Run did not complete from 0 to the requested 120 s.');
    [run.history, run.fields] = saved_states(run.data);
    assert(size(run.history, 2) == expected_columns, ...
        'Numeric exports do not cover the expected complete state history.');
    run.completed = true;
catch cause
    run.runtime = toc(run_timer);
    run.error = error_text(cause); % Includes critical-state errors; never clip/retry a state.
end
end

function [history, names] = saved_states(data)
% Both hosts export every xout column, including filters and the last vent state.
names = sort(fieldnames(data));
keep = false(size(names));
blocks = cell(size(names));
for k = 1:numel(names)
    value = data.(names{k});
    if strcmp(names{k}, 't') || ~isnumeric(value), continue; end
    assert(isa(value, 'double') && isreal(value) && ismatrix(value) && ...
        size(value, 1) == numel(data.t) && all(isfinite(value(:))), ...
        'Invalid saved state field %s.', names{k});
    keep(k) = true;
    blocks{k} = value;
end
names = names(keep);
history = [blocks{keep}];
end

function [identical, differences, max_state_difference, max_time_difference] = compare_histories(a, b)
identical = false;
differences = NaN;
max_state_difference = Inf;
max_time_difference = Inf;
if ~isequal(a.fields, b.fields) || ~isequal(size(a.history), size(b.history)) || ...
        ~isequal(size(a.data.t), size(b.data.t))
    return; % Different adaptive grids/shapes fail; do not interpolate either run.
end
state_bits_a = typecast(a.history(:), 'uint64');
state_bits_b = typecast(b.history(:), 'uint64');
time_bits_a = typecast(a.data.t(:), 'uint64');
time_bits_b = typecast(b.data.t(:), 'uint64');
differences = nnz(state_bits_a ~= state_bits_b)+nnz(time_bits_a ~= time_bits_b);
max_state_difference = max(abs(a.history(:)-b.history(:)));
max_time_difference = max(abs(a.data.t(:)-b.data.t(:)));
identical = differences == 0;
end

function cleanup_run(waitbars_before)
% A host may fail before publishing its local waitbar in base LH2Model.
% Handle the custom and built-in tags, preserving pre-existing waitbars.
waitbars_before = waitbars_before(isgraphics(waitbars_before));
waitbars = model_waitbars();
for k = 1:numel(waitbars)
    if ~any(waitbars(k) == waitbars_before)
        delete(waitbars(k));
    end
end
reset_globals();
end

function handles = model_waitbars()
handles = findall(groot, 'Type', 'figure', '-regexp', 'Tag', '^(waitbar|TMWWaitbar)$');
end

function reset_globals()
evalin('base', ['clear global ETTVentState ET_fill_complete ST_ready ' ...
    'ST_vent_complete ET_vent_complete Process_complete']);
end

function result = record(name, passed, numbers)
result = struct('name', name, 'passed', logical(passed), 'numbers', numbers);
end

function text = error_text(cause)
text = sprintf('%s: %s', cause.identifier, regexprep(cause.message, '\s+', ' '));
end

function status = pass_fail(passed)
if passed, status = 'PASS'; else, status = 'FAIL'; end
end
