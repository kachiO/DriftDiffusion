% DriftDiffusion Class
%
% Params contains general params and acc noise
% Run DD with 1 directtion (1 delta) or 2 directions (2 deltas, 1 sMu,sSig)
% For one modality, create second object for second modality
%
% Properties
% model % Model to use
% func % Eq for model
% seed % Simple value for seed
% seedDetails % Actual seed generated by rng(seed)
% output % Output
% finished = 0; % Finished
% it % Current iteration
% its % Total iterations
% aNoise % Vector of acc noise
% aMu % Mean of accumulator noise
% aSig % std of accumulator noise
% aLam % Acc auto-regressive parameter
% sNoise % Vector of sensory noise
% sMu % Mean of sensory noise
% sSig % std of sensory noise
% initialParams % Save specified params
% delta1 % Evidence dimension 1
% delta2 % Evidence dimension 2
% fig = NaN % Handle to plot
% contPlot % Update plot on each step?
%
% Models
% Delta1D
% Acc noise only, 1 direction. Stim noise in delta.
% Delta2D
% Acc noise only, 2 directions. Stim noise in delta.
% BB1D
% Acc noise, 1 direction. Stim noise applied to delted in model;
% BB2D
% Acc noise, 2 direction. Stim noise applied to delted in model;

classdef DD < handle
    properties
        model % Model to use
        func % Eq for model
        seed % Simple value for seed
        seedDetails % Actual seed generated by rng(seed)
        output % Output
        decMadeAt % It decision made on (RT)
        dec % Decision made
        finished = 0; % Finished
        it % Current iteration
        its % Total iterations
        aNoise % Vector of acc noise
        aMu % Mean of accumulator noise
        aSig % std of accumulator noise
        aLam % Acc auto-regressive parameter
        sNoise1 % Vector of sensory noise direction 1
        sNoise2 % Vector of sensory noise direction 2
        sMu % Mean of sensory noise
        sSig % std of sensory noise
        initialParams % Save specified params
        delta1 % Evidence direction 1
        delta2 % Evidence direction 2
        fig = NaN % Handle to plot
        contPlot % Update plot on each step?
        plotSpeed % Plot update speed
        decBoundMode % Type of decision bound
        decBound % Decision bound value (static)
        decBoundSEMulti % Factor to * SE by (SE)
        outputDecBound % Decbound val for each output step
        dbReached % Was decision boundary reached?
        expDecBoundScale % When using ExpDecay, scale factor
        decFunc % Function to use for dec boundary
        decFuncParams % Params for specified function
        evs % Eval string for decFunc and params
        robust = 'Off'
        robustFunc = @DD.robustNull;
        robustOpts = struct;
        testProp = DD.setTestProp % Ignore
        template
    end
    
    properties (Constant = true)
        testProp2 = 1;
    end
    
    methods
        function obj = DD(params, stim) % Initialise
            if isfield(params, 'template') && ~isempty(params.template)
               % A template has been specified
               % Apply the template paramaters, overwriting those already
               % in params
               % Then continue to set params as specified, or as default
               params = obj.setTemplate(params);
               obj.template = params.template;
            else
                obj.template = 'Custom';
            end
            obj.initialParams = params;
            
            % Has number of iterations been specified?
            if isfield(params, 'its')
                obj.its = params.its;
            else % Default 500
                obj.its = 500;
            end
            
            % If a fig is specified in params, plot there
            if isfield(params, 'fig') ...
                    && isa(params.fig, 'matlab.ui.Figure')
                obj.fig = params.fig;
                figure(obj.fig);
            else
                % If no figure is specified, do nothing; create if .plotDD
                % is called
            end
            
            % Has contPlot been specified?
            if isfield(params, 'contPlot')
                obj.contPlot = params.contPlot;
            else % Default on
                obj.contPlot = 1;
            end
            % Has plotSpeed been specified?
            if isfield(params, 'plotSpeed')
                obj.plotSpeed = params.plotSpeed;
            else % Default plot each iteration
                obj.plotSpeed = 2;
            end
            
            % Set robust option
            if ~isfield(params, 'robust')
                % Already set as defaults
                % obj.robust = 'off';
                % obj.robustFunc = @obj.robustNull;
                % obj.robustOpts = [];
            else
                obj.robust = params.robust;
                switch lower(params.robust)
                    case 'threshold'
                        obj.robustFunc = @DD.robustThresh;
                        obj.robustOpts = params.robustOpts;
                    case 'linear'
                    case 'exp'
                end
            end
            
            % Has model been specified?
            % Also resets/preallocates .output using .its
            % And resets/sets the seed
            obj = obj.setModel(params, stim);
            
            obj = obj.setDecBound(params);
            
        end
        
        function obj = setModel(obj, params, stim) % Set the model
            % Also resets/preallocates .output using .its
            % And resets/sets the seed
            if isfield(params, 'model')
                obj.model = params.model;
            else
                % Set default model
                obj.model = 'Delta1D';
            end
            
            % Set common params
            if isfield(params, 'aMu')
                obj.aMu = params.aMu;
            else
                obj.aMu = 0;
            end
            if isfield(params, 'aSig')
                obj.aSig = params.aSig;
            else
                obj.aSig = rand/10;
            end
            if isfield(params, 'aLam')
                obj.aLam = params.aLam;
            else
                obj.aLam = 1;
            end
            if isfield(params, 'sSig')
                obj.sSig = params.sSig;
            else
                obj.sSig = 1;
            end
            if isfield(params, 'sMu')
                obj.sMu = params.sMu;
            else
                obj.sMu = 1;
            end
            
            % Set model specific params
            switch obj.model
                case 'ARGuass'
                    % Autoregressive, no stim, 3 param
                    % aMu, aSig, aLam; already set
                    obj.func = 'a(t) = aLam * a(t-1) + aNoise(t)';
                    params.dims = 1;
                    
                case 'Delta1D'
                    % Accumulator noise only, stim input (1D)
                    % aMu, aSig, aLam; already set
                    % delta1; set
                    obj.func = ...
                        'a(t) = aLam * a(t-1) + aNoise(t) + delta1(t)';
                    params.dims = 1;
                    
                    % Set up deltas
                    if isfield(stim, 'delta1')
                        obj.delta1 = stim.delta1;
                    else
                        obj.delta1 = obj.generateDelta(0.97, 1);
                    end
                    obj.delta2 = NaN(1, obj.its);
                    obj.sNoise1 = zeros(1, obj.its);
                    obj.sNoise2 = NaN(1, obj.its);
                    
                case 'Delta2D'
                    % Accumulator noise only, stim input (2D)
                    % Stim noise accounted for in delta
                    % aMu, aSig, aLam; already set
                    % delta1, delta2; set
                    obj.func = ...
                        'a(t) = aLam * a(t-1) + aNoise(t) + delta1(t) + delta2(t)';
                    params.dims = 2;
                    
                    % Set up deltas
                    if isfield(stim, 'delta1')
                        obj.delta1 = stim.delta1;
                    else
                        obj.delta1 = obj.generateDelta(0.97, 1);
                    end
                    if isfield(stim, 'delta2')
                        obj.delta2 = stim.delta2;
                    else
                        obj.delta2 = obj.generateDelta(0.99, -1);
                    end
                    obj.sNoise1 = zeros(1, obj.its);
                    obj.sNoise2 = zeros(1, obj.its);
                    
                case 'BB1D' % Brunton basic 1 Direction
                    % Accumulator and sensory noise, stim input (1D)
                    % aMu, aSig, aLam; already set
                    % sMu, sSig, delta1; set
                    obj.func = ...
                        'a(t) = aLam * a(t-1) + aNoise(t) + delta1(t)*sNoise(t)';
                    params.dims = 1;
                    
                    % Set up deltas - no noise
                    if isfield(stim, 'delta1')
                        obj.delta1 = stim.delta1;
                    else
                        obj.delta1 = obj.generateDelta(0.97, 1);
                    end
                    obj.delta2 = NaN(1, obj.its);
                    % Set up stim noise
                    % obj = obj.setStimNoise(obj, params);
                    % Set stim noise
                    obj.sNoise1 = ...
                        obj.generateStimNoise(obj.sMu, obj.sSig);
                    obj.sNoise2 = ...
                        NaN(1, obj.its);
                    
                    % Set up stim noise
                    obj.sNoise1 = ...
                        obj.generateStimNoise(obj.sMu, obj.sSig);
                    obj.sNoise2 = [];
                    
                    
                case 'BB2D' % Brunton basic 2 direction
                    % Accumulator and sensory noise, stim input (1D)
                    % aMu, aSig, aLam; already set
                    % sMu, sSig, delta1, delta2; set
                    obj.func = ...
                        'a(t) = aLam * a(t-1) + aNoise(t) + (delta1(t)+delta2(t))*sNoise(t)';
                    params.dims = 2;
                    
                    % Set up deltas - no noise
                    if isfield(stim, 'delta1')
                        obj.delta1 = stim.delta1;
                    else
                        obj.delta1 = obj.generateDelta(0.97, 1);
                    end
                    if isfield(stim, 'delta2')
                        obj.delta2 = stim.delta2;
                    else
                        obj.delta2 = obj.generateDelta(0.99, -1);
                    end
                    % Set up stim noise
                    % obj = obj.setStimNoise(obj, params);
                    % Set stim noise
                    obj.sNoise1 = ...
                        obj.generateStimNoise(obj.sMu, obj.sSig);
                    obj.sNoise2 = ...
                        obj.generateStimNoise(obj.sMu, obj.sSig);
                    
                case 'BruntonFull' % Adaptation, 2 directions
                    params.dims = 2;
            end
            
            % When model is set, reset output (and seed)
            obj = obj.resetOutput(params);
            
            % Generate acc noise
            if ~isnan(obj.aMu)
                obj.aNoise = obj.aSig*randn(1, obj.its) + obj.aMu;
            end
            
            % Initialise first values
            obj.it = 1; % Run first it...
            obj.output(obj.it) = obj.aMu; % ... Run
            
        end
        
        function obj = setDecBound(obj, params) % Set decision bounds
            
            if isfield(params, 'decBoundMode')
                obj.decBoundMode = params.decBoundMode;
            else
                % Turn off
                obj.decBoundMode = 'Off';
            end
            
            switch obj.decBoundMode
                case 'Off'
                    obj.decBound = NaN;
                    obj.decBoundSEMulti = NaN;
                case 'Static'
                    if isfield(params, 'decBound')
                        obj.decBound = params.decBound;
                    else
                        % Set default
                        obj.decBound = 10;
                    end
                    obj.decBoundSEMulti = NaN;
                    obj.outputDecBound(1) = obj.decBound;
                case 'LinearDecay'
                    if isfield(params, 'decBound')
                        obj.decBound = params.decBound;
                    else
                        % Set default
                        obj.decBound = 10;
                    end
                    obj.decBoundSEMulti = NaN;
                    obj.outputDecBound = ...
                        linspace(obj.decBound, 0, obj.its);
                case 'ExpDecay'
                    if isfield(params, 'decBound')
                        obj.decBound = params.decBound;
                    else
                        % Set default
                        obj.decBound = 10;
                    end
                    if isfield(params, 'expDecBoundScale')
                        obj.expDecBoundScale = params.expDecBoundScale;
                    else
                        % Set default
                        obj.expDecBoundScale = 10;
                    end
                    % Not yet working
                    obj.outputDecBound = ...
                        obj.decBound ...
                        * (0-log(linspace(0, obj.decBound, ...
                        obj.its)));
                    % Normalise up to decBound
                    obj.outputDecBound = ...
                        (obj.outputDecBound - min(obj.outputDecBound)) ...
                        ./ (max(obj.outputDecBound(~isinf(obj.outputDecBound)))-min(obj.outputDecBound(~isinf(obj.outputDecBound))));
                case 'SE'
                    if isfield(params, 'decBoundSEMulti')
                        obj.decBoundSEMulti = params.decBoundSEMulti;
                    else
                        % Set default
                        obj.decBoundSEMulti = 30;
                    end
                    obj.decBound = NaN;
                case 'ExpDecaySE'
                    % Not yet implemented
                case 'Custom'
                    if isfield(params, 'decFunc')
                        if isfield(params, 'decBound')
                            obj.decBound = params.decBound;
                        else
                            % Set default
                            obj.decBound = 10;
                        end
                        obj.decFunc = params.decFunc;
                        obj.decFuncParams = params.decFuncParams;
                    else
                        % Set default (Linear decay, single point)
                        obj.decBound = params.decBound;
                        obj.decFunc = @(dbs,dbe,its,it) ...
                            dbs - it*((dbs-dbe)/(its-1));
                        
                        obj.decFuncParams = [obj.decBound, 0, obj.its];
                        
                        % Defualt is linear, can preallocate but these
                        % functions should run on each iteration
                        % So don't calculate here, do in iterate
                        obj.outputDecBound = NaN(1,obj.its);
                        
                    end
                    
                    % Create command to execute
                    % Create eval string - is there a better way to do
                    % this?
                    evs = ['obj.outputDecBound(obj.it) = ', ...
                        'obj.decFunc(']; 
                    for pm = 1:length(obj.decFuncParams)
                        evs = [evs, 'obj.decFuncParams(', ...
                            num2str(pm), '), ']; 
                    end
                    obj.evs = [evs, 'obj.it);'];
                    
            end
        end
        
        function obj = resetOutput(obj, params) % Reset output
            obj.output = NaN(1, obj.its);
            obj.outputDecBound = NaN(1, obj.its);
            obj.dbReached = 0;
            obj.decMadeAt = NaN;
            obj.dec = NaN;
            obj = obj.resetSeed(params);
        end
        
        function obj = resetSeed(obj, params) % Set/reset seed
            if isfield(params, 'seed')
                obj.seed = params.seed;
            else % Default new
                obj.seed = rand*now;
            end
            % Set seed here
            rng(obj.seed); rng(obj.seed);
            % Save details
            obj.seedDetails = rng(obj.seed);
        end
        
        function delta = generateDelta(obj, prop, dir) % Generate stimulus
            % Direction = 1 or -1
            % if dir == 1
            %     delta = (rand(1, obj.its) > prop);
            % else
            %     delta = (0-(rand(1, obj.its) > prop));
            % end
            delta = dir * (rand(1, obj.its) > prop);
        end
        
        function sNoise = generateStimNoise(obj, sMu, sSig)
            % Generate noise for stimulus
            sNoise = sSig*randn(1, obj.its) + sMu;
        end
        
        function obj = iterate(obj, steps) % Run set no. of its
            % Iterate from obj.it to obj.it+steps
            st = obj.it+1;
            if obj.it+steps > obj.its
                ed = obj.its;
            else
                ed = obj.it+steps;
            end
            
            for i = st:ed
                switch obj.model
                    case 'ARGuass'
                        obj.output(i) = ...
                            obj.aLam*obj.output(i-1) + obj.aNoise(i); % A
                    case 'Delta1D' % Robust implemented
                        % obj.output(i) = ...
                        %     obj.aLam*obj.output(i-1) + obj.aNoise(i) ... A
                        %     + obj.delta1(i); % S
                        
                        % Get value to add depending on robust settings
                        addVal = ...
                            obj.robustFunc(obj.aNoise(i), ...
                            obj.delta1(i), '+', obj.robustOpts);
                        
                         obj.output(i) = ...
                             obj.aLam*obj.output(i-1) + addVal;
                        
                    case 'Delta2D'
                        obj.output(1,i) = ...
                            obj.aLam.*obj.output(i-1) + obj.aNoise(i) ... A
                            + obj.delta1(i) + obj.delta2(i); % S
                    case 'BB1D' % Robust implemented
                        % obj.output(i) = ...
                        %     obj.aLam*obj.output(i-1) + obj.aNoise(i) ... A
                        %    + obj.delta1(i)*obj.sNoise(i); % S

                        addVal = ...
                            obj.robustFunc(obj.sNoise1(i), ...
                            obj.delta1(i), '*', obj.robustOpts);
                        
                        % Checking
                        if obj.delta1(i)>0 && addVal == 0
                           % keyboard 
                        end
                        
                        obj.output(i) = ...
                            obj.aLam*obj.output(i-1) + obj.aNoise(i) ...
                            + addVal;
                        
                    case 'BB2D' % Wrong - not implemented yet
                        obj.output(i) = ...
                            obj.aLam*obj.output(i-1) + obj.aNoise(i) ... A
                            +(obj.delta1(i)+obj.delta2(i))*obj.sNoise(i);%S
                    case 'BruntonFull'
                        % Pass - not implemented yet
                end
                % Update it
                obj.it = i;
                
                % Iterate decision boundary
                switch obj.decBoundMode
                    case 'Static'
                        obj.outputDecBound(i) = obj.decBound;
                    case 'SE'
                        obj.outputDecBound(i) = ...
                            (std(obj.output(st:i))/sqrt(i-st)) * 20;
                    case 'Linear'
                        % Already fully pre-iterated
                    case 'Exp'
                        
                    case 'Other'
                        obj.outputDecBound(i) = obj.decBound ...
                            - std(obj.output(st:i))/sqrt(i-st);
                    case 'Custom'
                        % Function defined in obj.decFunc
                        % Uses the params in obj.decFuncParams in order
                        % Function must be designed for single output
                        % Last function input should be obj.it
                        
                        % Fixed example
                        % obj.outputDecBound(obj.it) = ...
                        % obj.decFunc(...
                        % obj.decFuncParams(1), ...
                        % obj.decFuncParams(2), ...
                        % obj.decFuncParams(3), ...
                        % obj.it ...
                        % );
                        
                        % Using evalString
                        
                        eval(obj.evs)
                end
                
                % Check decision boundaries
                % (Only after at least 10% of way through)
                if (obj.output(i) >= obj.outputDecBound(i) ...
                        && obj.it > obj.its*0.1) ...
                        || (obj.output(i) <= 0-obj.outputDecBound(i) ...
                        && obj.it > obj.its*0.1) ...
                        || obj.dbReached == 1
                    
                    obj.dbReached = 1;
                    if isnan(obj.dec) % First time?
                        obj.decMadeAt = obj.it;
                        obj.dec = obj.output(i);
                    end
                    obj.output(i) = obj.dec;
                end
                
                % Update plot
                if obj.contPlot == 1 && ~mod(obj.it, obj.plotSpeed)
                    obj = obj.plotDD;
                end
                
            end
            
            % Update finished
            obj = obj.markFinIfFin;
            
        end
        
        function obj = markFinIfFin(obj) % Update .finished
            % Check if final iteration has been run, if so mark finished
            % Check if decision boundary has been reached, if so mark as
            % finished
            if obj.it == obj.its
                obj.finished = 1;
                % If decision bound hasn't been reached, set final decision
                % values
                if isnan(obj.dec) 
                    obj.decMadeAt = obj.it;
                    obj.dec = obj.output(obj.it);
                end
            else
                obj.finished = 0;
            end
        end
        
        function obj = run(varargin) % Run all remaining steps or spec
            
            obj = varargin{1};
            
            if numel(varargin) == 2 % Steps specified?
                steps = varargin{2};
            else % No, set defualts
                steps = obj.its-obj.it; % Remaining
            end
            
            obj = obj.iterate(steps);
            
        end
        
        function obj = plotDD(obj)
            % Standard output and 2 delta plot
            % Plots are 4x1
            % [1,2,4,5] main plot
            mp = 1:2;
            % [7, 8] Dim 1 sense
            lp = 3;
            % [3, 6] Dim 2 sens
            sp = 4;
            % [9] Params
            % pp = 9;
            
            % Select or create figure
            if isa(obj.fig, 'matlab.ui.Figure')
                % Figure exists, select
                try
                    figure(obj.fig)
                catch
                    % Failed, must have been closed
                    % Create new
                    obj.fig = figure;
                end
            else
                % Figure doesn't exist yet, create
                obj.fig = figure;
            end
            hold on
            
            xAx = 1:obj.it;
            
            % Main plot
            subplot(4,1, mp),
            cla
            scatter(xAx(1:obj.it), obj.output(1:obj.it))
            hold on
            plot(xAx(1:obj.it), obj.output(1:obj.it))
            plot(xAx(1:obj.it), obj.outputDecBound(1:obj.it))
            plot(xAx(1:obj.it), 0-obj.outputDecBound(1:obj.it))
            title('Accumulator')
            ylabel('Decision variable')
            
            % Delta 1 plot
            subplot(4,1,lp), cla
            plot(xAx, obj.delta1(1:obj.it))
            hold on
            line([obj.it, obj.it], [-1, 1], ...
                'color', 'r', 'LineWidth', 2)
            title('Stimulus 1')
            ylabel('Mag.')
            
            % Delta 2 plot
            subplot(4,1,sp), cla
            plot(xAx, obj.delta2(1:obj.it))
            hold on
            line([obj.it, obj.it], [-1, 1], ...
                'color', 'r', 'LineWidth', 2)
            title('Stimulus 2')
            xlabel('Time')
            ylabel('Mag.')
            
            drawnow
            
        end
        
        function [obj, DD2] = plotDD2(obj, DD2)
            figure
            % Takes a second DD object and makes a 2D (modality) plot
            % Objects assumed to be complete, check
            if obj.finished ~= 1
                % Run silently
                temp = obj.contPlot;
                obj.contPlot = 0;
                obj = obj.run;
                obj.contPlot = temp;
            end
            if DD2.finished ~= 1
                % Run silently
                temp = DD2.contPlot;
                DD2.contPlot = 0;
                DD2 = DD2.run;
                DD2.contPlot = temp;
            end
            
            
            % Plots are 3x3, deltas on same plot per modality
            % [1,2,4,5] main plot
            mp = [1, 2, 4, 5];
            % [7, 8] Dim 1 sense
            lp = [7, 8];
            % [3, 6] Dim 2 sens
            sp = [3, 6];
            % [9] Params - not yet added
            % pp = 9;
            maxIt = max([obj.it, DD2.it]);
            xAx = 1:maxIt;
            % maxAx = max([obj.output(1:maxIt), DD2.output(1:maxIt), ...
            %     obj.outputDecBound(1:maxIt), DD2.outputDecBound(1:maxIt)]);
            % minAx = min([obj.output(1:maxIt), DD2.output(1:maxIt), ...
            %     obj.outputDecBound(1:maxIt), DD2.outputDecBound(1:maxIt)]);
            
            % If calling object is set to continous plot, loop here
            % Else, just plot the whole thing in one go
            if obj.contPlot == 1
                pRange = 1:maxIt;
            else
                pRange = maxIt;
            end
            for pr = pRange
                if ~mod(pr, obj.plotSpeed)
                    clf
                    hold on
                    
                    % Main plot
                    subplot(3,3, mp),
                    cla
                    scatter(obj.output(1:pr), DD2.output(1:pr))
                    hold on
                    plot(obj.output(1:pr), DD2.output(1:pr))
                    line([obj.outputDecBound(pr), ...
                        obj.outputDecBound(pr)], ...
                        [0, obj.output(pr)]);
                    line([0, DD2.output(pr)], ...
                        [DD2.outputDecBound(pr), ...
                        DD2.outputDecBound(pr)]);
                    % plot(obj.outputDecBound(1:pr), ...
                    %      DD2.outputDecBound(1:pr))
                    % plot(0-obj.outputDecBound(1:pr), ...
                    %      0-DD2.outputDecBound(1:pr))
                    % plot(pr, ...
                    %     obj.outputDecBound(1:pr))
                    % plot(DD2.outputDecBound(1:pr), pr)
                    title('Accumlator 1 vs Accumulator 2')
                    ylabel('Mod. 2')
                    xlabel('Mod. 1')
                    
                    
                    % Plots up to max of complete its from each model
                    
                    % Plots up to max of what's been plotted so far
                    
                    maxAxP = max([obj.output(1:pr), DD2.output(1:pr), ...
                        obj.outputDecBound(pr), DD2.outputDecBound(pr)]);
                    minAxP = min([obj.output(1:pr), DD2.output(1:pr), ...
                        obj.outputDecBound(pr), DD2.outputDecBound(pr)]);
                    
                    axis([minAxP, maxAxP, minAxP, maxAxP])
                    
                    % Modality 1 plot - calling object
                    subplot(3,3,lp), cla
                    plot(xAx, [obj.delta1(1:maxIt)', obj.delta2(1:maxIt)'])
                    hold on
                    line([pr, pr], [-1, 1], ...
                        'color', 'r', 'LineWidth', 2)
                    title('Mod. 1')
                    ylabel('Mag.')
                    xlabel('Time')
                    
                    % Modality 2 plot - additional object
                    subplot(3,3,sp), cla
                    plot([DD2.delta1(1:maxIt)', DD2.delta2(1:maxIt)'], xAx)
                    hold on
                    line([-1, 1], [pr, pr], ...
                        'color', 'r', 'LineWidth', 2)
                    ylabel('Time')
                    xlabel('Mag.')
                    title('Mod. 2')
                    
                    drawnow
                end
            end
            legend({'Stim. 1', 'Stim. 2'})
            
            % Need to add decision bound checking
            % Set lines on graph to stop decreasing when modality decision
        end
        
        function obj = reset(obj) % Reset
            % Reset DD using original parameters and stim
            % CHANGES SEED
            obj.its = 1;
            params = obj.initialParams;
            stim = [obj.delta1; obj.delta2];
            obj = obj.setModel(params, stim);
        end
        
        function reRun(obj)
            % Replot without recalc
            % Seed not changed
            temp = obj.output;
            
            for i = 2:obj.its
                obj.it = i;
                obj.output = temp(1:i);
                obj = plotDD(obj);
            end
        end
        
    end
    
    methods (Static)
        function obj = setTestProp(x)
            disp('Setting testProp')
            obj.testProp = 'Set';
        end
        
       
        function params = setTemplate(params)
            % Set template - static for external access
            % Sets all parameters for specified template
            % Can be called from outside to set template, then replace
            % paramaters as needed before object creation
            switch params.template
                case 'Delta2D_CustomLin'
                    % Sensory information in two directions
                    % Accumulator noise (no sensory noise)
                    % Linearly decaying decision bounds (custom function
                    % example)

                    % Params
                    params.model = 'Delta2D'; % Accumulator model
                    params.plotSpeed = 5; % Plot every x iterations
                    params.its = 200;
                    params.aSig = 0.25; % Accumulator noise magnitude
                    params.aMu = 0;  % Accumulator noise bias
                    params.aLam = 1; % Autoregressive parameter (0<1, accumulator becomes leaky)
                    params.fig = figure;
                    % params1.decBoundMode = 'SE';
                    % params1.decBoundSEMulti = 2000;
                    % params1.decBoundMode = 'Static';
                    params.decBound = 50; % Initial decision bound magnitude
                    % The decision bounds in this example decay linearlly, which can be
                    % specified with .decBoundMode = 'Linear'. However, below is an example of
                    % doing the same thing by specifying a custom function.
                    params.decBoundMode = 'Custom';
                    params.decFunc = @(dbs,dbe,its,it) ...
                        dbs - it*((dbs-dbe)/(its-1));
                    params.decFuncParams = [params.decBound, 0, params.its];
                case 'Delta2D_SE'
                    % Sensory information in two directions
                    % Accumulator noise (no sensory noise)
                    % SE decision bounds
                    
                    params.model = 'Delta2D';
                    params.plotSpeed = 5;
                    params.its = 200;
                    params.aSig = 0.1;
                    params.aMu = 0;
                    params.aLam = 1;
                    params.fig = figure;
                    params.decBoundMode = 'SE';
                    params.decBoundSEMulti = 1000;
                case 'Delta2D'
                    % Sensory information in two directions
                    % Accumulator noise (no sensory noise)
                    % No decision bounds
                    params.model = 'Delta2D';
                    params.plotSpeed = 5;
                    params.its = 200;
                    params.aSig = 0.1;
                    params.aMu = 0;
                    params.aLam = 1;
                    params.fig = figure;
                case 'BB1D_Robust'
                    % Stimulus in one direction
                    % Brunton 2013 model, without adaptaion
                    % No decision bounds
                    % Adds robustness to accumulator
                    
                    % Params
                    params.model = 'BB1D';
                    params.plotSpeed = 5;
                    params.its = 200;
                    params.aSig = 0.01;
                    params.sMu = 1;
                    params.sSig = 1;
                    params.aMu = 0;
                    params.aLam = 1;
                    params.fig = figure;
                    
                    params.decBoundMode = 'Off';
                    
                    params.robust = 'Threshold';
                    params.robustOpts.thresh = 0.6;
            end
            
            
        end
        
        % 
        function addVal = robustNull(delta, noise, trans, ~)
            % Take delta(t) and noise(t)
            % Return straight transform
            % Either + or - depending on if acc or sens noise
            % Ignore any robustOpts input - should be empty
            % Not sure how much sense applying robustness to + (ie. acc
            % noise) makes, but it's possible.
            switch trans
                case '+'
                    addVal = delta+noise;
                case '*'
                    addVal = delta*noise;
            end
        end
        
        function addVal = robustThresh(delta, noise, trans, robustOpts)
            % Take delta(t) and noise(t)
            % Return robust transform based on threshold option
            
            % First do normal operation
            addVal = DD.robustNull(delta, noise, trans, []);
            
            % Then zero if |addVal| is < thresh
            addVal(abs(addVal)<robustOpts.thresh) = 0;
        end
        
    end
end