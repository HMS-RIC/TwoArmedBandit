function runTriplePortExperiment_laser_state(varargin)

    %% State-Machine version of the triple-port experiment
    % previous versions by Ofer Mazor, Shay Neufeld, and others
    % v6, Ofer Mazor, 2021-09-22

    % print execution path
    fprintf ('Execution path: %s\n', mfilename('fullpath'));

    % Print debug log info to command line (true/false)
    global printLogToCommandLine
    printLogToCommandLine = false;

    global arduinoConnection arduinoPort
    global arduinoMessageString
    global p % parameter structure
    global info % structure containing mouse name and folder to be saved in
    global manualRewardTriggered manualRewardCount
    manualRewardTriggered = false;
    manualRewardCount = 0;

    % % Hard code laser stimulus profile for now
    % p.laserDelay = 0; % in ms
    % p.laserPulseDuration = 500; % in ms
    % p.laserPulsePeriod = 500; % in ms

    %% Setup

    % Cleanup routine to be executed upon termination (even if this function
    % is terminated early)
    finishup = onCleanup(@triplePortCleanup);

    % Seed random number generator (to prevent repeating the same values on
    % different experiments)
    rng('shuffle');

    % Set up logging
    mouseName = info.mouseName;
    mouseLog = strcat(mouseName,'_log'); % log file name
    setupLogging(mouseLog);


    % Log all paramters and inital values
    fn = fieldnames(p);
    for i=1:length(fn)
        fName = fn{i};
        logValue(fName,p.(fName));
    end
    rngState = rng;
    logValue('RNG Seed', rngState.Seed);
    logValue('RNG Type', rngState.Type);


    %% set up Arduino
    global arduinoConn
    try
        delete(arduinoConn);
    end
%     if ~isempty(arduinoConn)
%         fclose(arduinoConn);
%     end
    baudRate = 115200;
    arduinoConn = ArduinoConnection(@interpretArduinoMessage, baudRate);
    if isempty(arduinoConn.serialConnection)
        arduinoConn = [];
        return
    end

    %% setup ports/arduino
    global centerPort rightPort leftPort syncPort

    centerPort = NosePort(5,13);
    centerPort.setLEDPin(8);
    centerPort.setLaserPin(12);
    centerPort.deactivate();
    centerPort.noseInFunc = @noseIn;
    logValue('center port ID', centerPort.portID);

    rightPort = NosePort(7,4);
    rightPort.setLEDPin(10); % <-- change back to 10
    rightPort.setLaserPin(12);
    rightPort.setRewardDuration(p.rewardDurationRight);
    rightPort.setToSingleRewardMode();
    rightPort.rewardFunc = @rewardFunc;
    rightPort.noseInFunc = @noseIn;
    logValue('right port ID', rightPort.portID);

    leftPort = NosePort(6,3);
    leftPort.setLEDPin(9);
    leftPort.setLaserPin(12);
    leftPort.setRewardDuration(p.rewardDurationLeft);
    leftPort.setToSingleRewardMode();
    leftPort.rewardFunc = @rewardFunc;
    leftPort.noseInFunc = @noseIn;
    logValue('left port ID', leftPort.portID);

    %% Laser stim parameters:

    if (p.sideLaserStimEndTrig == 1)
        rightPort.setLaserEndTrig_Time();
        leftPort.setLaserEndTrig_Time();
    elseif (p.sideLaserStimEndTrig == 2)
        rightPort.setLaserEndTrig_NoseOut();
        leftPort.setLaserEndTrig_NoseOut();
    elseif (p.sideLaserStimEndTrig == 3)
        rightPort.setLaserEndTrig_NoseIn();
        leftPort.setLaserEndTrig_NoseIn();
    else
        warning('p.sideLaserStimEndType: unknown value');
    end
    rightPort.setLaserStimDuration(p.sideLaserStimDuration) %ms
    leftPort.setLaserStimDuration(p.sideLaserStimDuration) %ms
    % Laser stimulus profile (hard coded for now):
    rightPort.setLaserDelay(p.laserDelay); %this is in milliseconds
    leftPort.setLaserDelay(p.laserDelay); %ms
    rightPort.setLaserPulseDuration(p.laserPulseDuration) %ms
    leftPort.setLaserPulseDuration(p.laserPulseDuration) %ms
    rightPort.setLaserPulsePeriod(p.laserPulsePeriod) %ms
    leftPort.setLaserPulsePeriod(p.laserPulsePeriod) %ms

    if (p.centerLaserStimEndTrig == 1)
        centerPort.setLaserEndTrig_Time();
    elseif (p.centerLaserStimEndTrig == 2)
        centerPort.setLaserEndTrig_NoseOut();
    elseif (p.centerLaserStimEndTrig == 3)
        centerPort.setLaserEndTrig_NoseIn();
    else
        warning('p.centerLaserStimEndType: unknown value');
    end
    centerPort.setLaserStimDuration(p.centerLaserStimDuration) %ms
    % Laser stimulus profile (hard coded for now):
    centerPort.setLaserDelay(p.laserDelay); %this is in milliseconds
    centerPort.setLaserPulseDuration(p.laserPulseDuration) %ms
    centerPort.setLaserPulsePeriod(p.laserPulsePeriod) %ms

    % create NosePort specifically for syncing with imaging
    % this object simply receives 5 volt pulses from the inscopix box
    % on pin 11. IE it treats like a IR beam and when it is detected (when
    % a 5 volt pulse comes in) it records like a nose poke.
    syncPort = NosePort(11,13);
    syncPort.deactivate()
    syncPort.noseInFunc = @syncIn;
    logValue('Sync port ID', syncPort.portID);

    global sync_counter
    sync_counter = 0;

    initializeRewardProbabilities();

    global pokeHistory pokeCount
    pokeCount = 0;
    pokeHistory= struct;

    global iti lastPokeTime
    iti = p.minInterTrialInterval;
    rewardWin = p.centerPokeRewardWindow;
    lastPokeTime = clock;

    %create stats structure for online analysis and visualization
    global stats printStatsFlag expectRewardFlag rewardFlagCount currTrialNum
    currTrialNum = 1;
    expectRewardFlag = false;
    rewardFlagCount = 0;
    printStatsFlag = false;
    % initialize the first entry of stats to be zeros
    stats = initializestats();
    cumstats = cumsumstats(stats);
    %create figure for online visualization
    global h
    h = initializestatsfig(cumstats);



    %% Set up Trial State Machine
    % Global variable TrialState will contain the name of the current state:
    %   'ITI'       Inter-Trial Interval: Forced no-poke period. Every poke resets timer.
    %                   Transition to START when no-poke condition is met.
    %
    %   'START'     Wait for center poke to initiate.
    %                   Transition to 'REWARD' upon center poke.
    %
    %   'REWARD_WINDOW' Within the reward window. Side pokes get probabilistically rewarded.
    %                   Transition to 'ITI' upon any poke or timeout.
    %
    %
    % To initiate a state transition call:
    %       stateTransitionEvent(<event>)
    % Where <event> is a poke/timeout/other even that might trigger a transition


    global TrialState
    TrialState = 'ITI';
    lastPokeTime = datevec(0); % force immediate transition from ITI to START

    %% RUN THE PROGRAM:
    % Runs as long as info.running has not been set to false via the "Stop
    % Experiment" button
    while info.running
        pause(0.1)
        % check for iti & reward timeouts every ~100ms
        if strcmp(TrialState, 'ITI') & (etime(clock, lastPokeTime) >= iti)
            stateTransitionEvent('itiTimeout');
        end
        if (    strcmp(TrialState, 'REWARD_WINDOW') & ...
                p.centerPokeTrigger & ...
                (etime(clock, lastPokeTime) >= rewardWin) )
            stateTransitionEvent('rewardTimeout');
        end
        % confirm that expected rewards are delivered
        if expectRewardFlag
            rewardFlagCount = rewardFlagCount + 1;
            if (rewardFlagCount > 3)
                warning 'Expected reward wasn''t delivered.'
                expectRewardFlag = false;
                rewardFlagCount = 0;
            end
        end
        % print stats after decision pokes (once reward is delivered)
        if (printStatsFlag && ~expectRewardFlag)
            printStats();
            printStatsFlag = false;
        end
    end

end % runTriplePortExperiment



%% stateTransitionEvent: transitions between states of the state machine
function newTrialState = stateTransitionEvent(eventName)
    global TrialState p
    global portRewardState expectRewardFlag printStatsFlag
    global currTrialNum

    newTrialState = '';

    % 1) Respond to events based on the current state
    switch TrialState
        case 'ITI'
            % Inter Trial Interval state
            % - wait for itiTimeout event before transitioning to START
            % - reset timer on every poke
            % - if in training mode (p.centerPokeTrigger == false),
            %     transition stright to REWARD_WINDOW
            switch eventName
                case {'centerPoke', 'leftPoke', 'rightPoke'}
                     logIncorrectPoke(eventName);
                     fprintf(' *  Poke Between Trials — %s \n', eventName);

                case 'itiTimeout'
                    if (p.centerPokeTrigger)
                        newTrialState = 'START';
                    else
                        newTrialState = 'REWARD_WINDOW';
                    end
            end

        case 'START'
            % Start state
            % - wait for central poke to transition to REWARD_WINDOW
            % - side pokes result in transition to ITI state
            switch eventName
                case 'centerPoke'
                    newTrialState = 'REWARD_WINDOW';
                    logInitiationPoke(eventName);
                    fprintf('\n\n***  Center Poke — Trial %i Initiated  ***\n', currTrialNum);
                case {'leftPoke', 'rightPoke'}
                    logIncorrectPoke(eventName);
                    newTrialState = 'ITI';
                    fprintf(' *  Side Poke — %s \n', eventName);
            end

        case 'REWARD_WINDOW'
            % Reward Window state
            % - wait for side pokes to deliver probabilistic reward
            % - center poke or reward-window-timeout result in aborted trial and transition to ITI state
            switch eventName
                case 'rewardTimeout'
                    if (p.centerPokeTrigger)
                        newTrialState = 'ITI';
                    end
                case 'centerPoke'
                    logIncorrectPoke(eventName);
                    newTrialState = 'ITI';
                    fprintf('***  Center Poke — Trial ABORTED  ***\n');
                case {'leftPoke', 'rightPoke'}
                    logDecisionPoke(eventName);
                    newTrialState = 'ITI';
                    printStatsFlag = true;
                    if ((strcmp(eventName, 'rightPoke') && (portRewardState(1))) || ...
                        (strcmp(eventName, 'leftPoke') && (portRewardState(2))))
                        fprintf('***  Decision Poke — %s  - REWARDED Trial ***\n', eventName);
                        expectRewardFlag = true;
                    else
                        fprintf('***  Decision Poke — %s  - UNREWARDED Trial ***\n', eventName);
                    end
            end

        otherwise
            warning('Unexpected state.')
    end

    % was laser active?
    global centerPort leftPort rightPort
    switch eventName
        case 'centerPoke'
            if centerPort.laserActive
                fprintf(' * Center Laser\n');
            end
        case 'leftPoke'
            if leftPort.laserActive
                fprintf(' * Side Laser\n');
            end
        case 'rightPoke'
            if rightPort.laserActive
                fprintf(' * Side Laser\n');
            end
    end

    % 2) State Transition (if needed)
    if ~strcmp(newTrialState,'')
        % DEBUG:
        % fprintf('***      TRANSITION:   Old: %s   Trigger: %s    New: %s\n', TrialState, eventName, newTrialState);
        TrialState = newTrialState;
    end

    % 3) Initialize new trial state (if needed)
    % Here is where we perform all initialization actions for a new
    % state that only need to be performed once, at the start of the
    % state (e.g., turning LEDs on/off).
    global activateLeft activateRight center_laser_state
    switch newTrialState
        case ''
            % didn't switch states; do nothing

        case 'ITI'
            centerPort.ledOff();
            leftPort.ledOff();
            rightPort.ledOff();
            deactivateCenterLaserStim();
            deactivateSideLaserStim();
            deactivateSidePorts();

        case 'START'
            centerPort.ledOn();
            leftPort.ledOff();
            rightPort.ledOff();
            activateCenterLaserStimWithProb(p.centerLaserStimProb);
            deactivateSideLaserStim();
            deactivateSidePorts();

        case 'REWARD_WINDOW'
            centerPort.ledOff();
            leftPort.ledOn();
            rightPort.ledOn();
            % set up rewards
            activateLeft = (rand <= p.leftRewardProb); % activate left port with prob = p.leftRewardProb
            activateRight = (rand <= p.rightRewardProb); % activate right port with prob = p.rightRewardProb
            activateSidePorts(activateLeft, activateRight);
            % set up laser
            if (p.sideLaserFollowsCenter)
                activateSideLaserStimWithProb(center_laser_state); % center_laser_state is {0, 1}
            else
                activateSideLaserStimWithProb(p.sideLaserStimProb);
            end
            deactivateCenterLaserStim();

        otherwise
            warning('Unexpected state.')
    end
end


%% Laser stim functions

function activateSideLaserStimWithProb(sideSitmProb)
    global rightPort leftPort side_laser_state
    if rand <= sideSitmProb
        rightPort.activateLaser();
        leftPort.activateLaser();
        side_laser_state = 1;
    else
        deactivateSideLaserStim();
    end
end

function deactivateSideLaserStim()
    global rightPort leftPort side_laser_state
    rightPort.deactivateLaser();
    leftPort.deactivateLaser();
    side_laser_state = 0;
end

function activateCenterLaserStimWithProb(centerStimProb)
    global centerPort center_laser_state
    if rand <= centerStimProb
        centerPort.activateLaser();
        center_laser_state = 1;
    else
        deactivateCenterLaserStim();
    end
end

function deactivateCenterLaserStim()
    global centerPort center_laser_state
    centerPort.deactivateLaser();
    center_laser_state = 0;
end

function activateSidePorts(activateLeft, activateRight)
    fprintf('Rewarded ports:  R:%g  L:%g \n', activateRight, activateLeft);
    global rightPort leftPort
    global portRewardState
    portRewardState = [activateRight, activateLeft];

    % activate only the desired port(s)
    if activateRight
        rightPort.activate();
    end
    if activateLeft
        leftPort.activate();
    end
end

function deactivateSidePorts()
    global rightPort leftPort
    global portRewardState
    portRewardState = [false false];

    % disp('deactivateSidePorts')
    rightPort.deactivate();
    leftPort.deactivate();
end

%% Nose In Functions
function syncIn(portID)
    % disp('syncIn')
    % simply count the inscopix frames in a global variable.
    global sync_counter
    sync_counter = sync_counter + 1;
    global sync_times
    sync_times(sync_counter) = now;
end

function noseIn(portID)
    global rightPort leftPort centerPort pokeCount
    % disp('noseIn')

    % Initiate appropriate state transition
    pokeCount = pokeCount+1; %increment pokeCount
    if portID == rightPort.portID
        stateTransitionEvent('rightPoke');
    elseif portID == leftPort.portID
        stateTransitionEvent('leftPoke');
    elseif portID == centerPort.portID
        stateTransitionEvent('centerPoke');
    end
end

function logIncorrectPoke(pokeSide)
    updatePokeStats(pokeSide, 0);
end

function logInitiationPoke(pokeSide)
    updatePokeStats(pokeSide, 1);
end

function logDecisionPoke(pokeSide)
    updatePokeStats(pokeSide, 2);
end

function updatePokeStats(pokeSide, pokeType)
    global p
    global pokeHistory pokeCount lastPokeTime
    global rightPort leftPort centerPort
    global activateLeft activateRight side_laser_state center_laser_state
    global stats currTrialNum
    global iti
    global h

    global sync_counter sync_frame
    sync_frame = sync_counter;

    % pokeCount: value should be correct. It is incremented in noseIn()
    pokeHistory(pokeCount).timeStamp = now;
    timeSinceLastPoke = etime(clock, lastPokeTime);
    %update the lastPokeTime
    lastPokeTime = clock;

    % Update pokeHistory and initiate appropriate state transition
    pokeHistory(pokeCount).timeStamp = now;
    switch pokeSide
        case 'rightPoke'
            pokeHistory(pokeCount).portPoked = 'rightPort';
        case 'leftPoke'
            pokeHistory(pokeCount).portPoked = 'leftPort';
        case 'centerPoke'
            pokeHistory(pokeCount).portPoked = 'centerPort';
        otherwise
            warning('Unexpected pokeSide')
    end

    pokeHistory(pokeCount).isTRIAL = pokeType;
    % isTRIAL == 0 means that the poke is 'incorrect' and not a trial
    % isTRIAL == 1 means that centerPort has correctly initiated trial
    % isTRIAL == 2 means that the poke is a decision poke

    % determine value for isTrial based on current TrialState
    if (pokeType == 2)
        pokeHistory(pokeCount).trialTime = timeSinceLastPoke;
        pokeHistory(pokeCount).leftPortStats.prob = p.leftRewardProb;
        pokeHistory(pokeCount).rightPortStats.prob = p.rightRewardProb;
        pokeHistory(pokeCount).leftPortStats.ACTIVATE = activateLeft;
        pokeHistory(pokeCount).rightPortStats.ACTIVATE = activateRight;
        pokeHistory(pokeCount).sideLaserState = side_laser_state;
        currTrialNum = currTrialNum + 1;
    elseif (pokeType == 1)
        pokeHistory(pokeCount).centerLaserState = center_laser_state;
    end

    % in order to run update stats, we need a value for pokeHistory.REWARD
    pokeHistory(pokeCount).REWARD = 0; % this will be overwritten if reward happens

    % how many manual rewards were delivered prior to this poke?
    global manualRewardCount
    pokeHistory(pokeCount).manualRewards = manualRewardCount;
    manualRewardCount = 0;

    % update stats and refresh figures
    stats = updatestats(stats,pokeHistory(pokeCount),pokeCount,sync_frame);
    global handlesCopy
    leftRewards = sum(stats.rewards.left);
    rightRewards = sum(stats.rewards.right);
    totalRewards = leftRewards + rightRewards;
    leftTrials = sum(stats.trials.left)/2;
    rightTrials = sum(stats.trials.right)/2;
    totalTrials = leftTrials + rightTrials;
    global numBlocks
    leftBlocks = numBlocks.left;
    rightBlocks = numBlocks.right;
    totalBlocks = leftBlocks+rightBlocks;
    data = [leftRewards, rightRewards, totalRewards; leftTrials, rightTrials, ...
        totalTrials;leftBlocks,rightBlocks,totalBlocks];
    set(handlesCopy.statsTable,'data',data);
    cumstats = cumsumstats(stats);
    updatestatsfig(cumstats,h,pokeCount);

    % if (pokeType == 2)
    %     fprintf ('           L      R    Tot\n')
    %     fprintf ('Trials:  %3i    %3i    %3i\n', leftTrials, rightTrials, totalTrials)
    %     fprintf ('Rewards: %3i    %3i    %3i\n', leftRewards, rightRewards, totalRewards)
    % end
end

function printStats()
    global stats
    leftRewards = sum(stats.rewards.left);
    rightRewards = sum(stats.rewards.right);
    totalRewards = leftRewards + rightRewards;
    leftTrials = sum(stats.trials.left)/2;
    rightTrials = sum(stats.trials.right)/2;
    totalTrials = leftTrials + rightTrials;

    fprintf ('           L      R    Tot\n')
    fprintf ('Rewards: %3i    %3i    %3i\n', leftRewards, rightRewards, totalRewards)
    fprintf ('Trials:  %3i    %3i    %3i\n', leftTrials, rightTrials, totalTrials)
end

%% Reward Function
function rewardFunc(portID)
    % disp('rewardFunc')
    global pokeHistory pokeCount stats sync_frame
    global h
    global currBlockReward

    % 1) Check for manually triggered reward
    global manualRewardTriggered manualRewardCount
    global expectRewardFlag rewardFlagCount
    if manualRewardTriggered
        fprintf('***  Manual Reward Delivered  ***\n');
        manualRewardTriggered = false;
        manualRewardCount = manualRewardCount + 1;
        return
    else
        expectRewardFlag = false;
        rewardFlagCount = 0;
        % No need to print this out. Should have already been detected as a Rewarded Decision Poke.
        % fprintf('***  REWARD Delivered  ***\n');
    end
    if (pokeCount == 0)
        % should never get here (unless a manual rewrd isn't caught above)
        warning('Reward delivered before first poke.');
        return;
    end

    % 2) If this is a mouse-generate reward (a true reward), then
    % attribute it to current poke and log it.
    currBlockReward = currBlockReward + 1;
    % display(currBlockReward)
    fprintf('Current block reward count: %i \n', currBlockReward);

    % log rewarded port to poke history
    pokeHistory(pokeCount).REWARD = 1;

    %update stats and refresh figures
    poke = pokeHistory(pokeCount);
    if poke.isTRIAL ~= 2
        % confirm that isTRIAL type is 2
        warning('Rewarded trial is not a decision trial.')
    end
    if strcmpi(poke.portPoked,'leftPort')
        stats.rewards.left(pokeCount) = 1;
    elseif strcmpi(poke.portPoked,'rightPort')
        stats.rewards.right(pokeCount) = 1;
    end

    leftRewards = sum(stats.rewards.left);
    rightRewards = sum(stats.rewards.right);
    totalRewards = leftRewards + rightRewards;
    leftTrials = sum(stats.trials.left)/2;
    rightTrials = sum(stats.trials.right)/2;
    totalTrials = leftTrials + rightTrials;
    global numBlocks
    leftBlocks = numBlocks.left;
    rightBlocks = numBlocks.right;
    totalBlocks = leftBlocks+rightBlocks;
    data = [leftRewards, rightRewards, totalRewards; leftTrials, rightTrials, ...
        totalTrials;leftBlocks,rightBlocks,totalBlocks];
    global handlesCopy
    set(handlesCopy.statsTable,'data',data);
    cumstats = cumsumstats(stats);
    updatestatsfig(cumstats,h,pokeCount);

    cumstats = cumsumstats(stats);
    updatestatsfig(cumstats,h,pokeCount);

    % fprintf (repmat('\b', 1, 27));
    % fprintf ('Rewards: %3i    %3i    %3i\n', leftRewards, rightRewards, totalRewards)

    reupdateRewardProbabilities();
end

function reupdateRewardProbabilities()
    global p
    global currBlockReward blockRange currBlockSize

    %reupdate reward probabilities if needed.
    if currBlockReward >= currBlockSize
        p.leftRewardProb = 1 - p.leftRewardProb;
        p.rightRewardProb = 1 - p.rightRewardProb;
        currBlockReward = 0;
        currBlockSize = randi([min(blockRange),max(blockRange)]);
        fprintf('\n** Reward Probabilities Switched **\n')
        fprintf('Left Reward Prob: %g \n', p.leftRewardProb)
        fprintf('Right Reward Prob: %g \n', p.rightRewardProb)
        fprintf('Current Block Size: %i \n\n', currBlockSize)
        global numBlocks
        if p.rightRewardProb >= p.leftRewardProb
            numBlocks.right = numBlocks.right + 1;
        else
            numBlocks.left = numBlocks.left + 1;
        end
    end
end

function initializeRewardProbabilities()
    % to be called once at the start of a session

    global p
    global currBlockReward blockRange currBlockSize

    global numBlocks
    numBlocks = struct;
    numBlocks.left = 0;
    numBlocks.right = 0;
    if p.rightRewardProb >= p.leftRewardProb
        numBlocks.right = 1;
    else
        numBlocks.left = 1;
    end

    currBlockReward = 0;
    blockRange = [p.blockRangeMin:p.blockRangeMax];
    currBlockSize = randi([min(blockRange),max(blockRange)]);
    fprintf('Left Reward Prob: %g \n', p.leftRewardProb)
    fprintf('Right Reward Prob: %g \n', p.rightRewardProb)
    fprintf('Current Block Size: %i \n\n', currBlockSize)

end


%% Cleanup
% Cleanup function is run when program ends (either naturally or after ctl-c)
function triplePortCleanup()
    disp('Cleaning up...')

    %turn all LEDs/lasers off
    global centerPort rightPort leftPort
    centerPort.ledOff();
    rightPort.ledOff();
    leftPort.ledOff();
    centerPort.deactivateLaser();
    rightPort.deactivateLaser();
    leftPort.deactivateLaser();

    %close log file
    global logFileID AllNosePorts
    fclose(logFileID);

    %deactivate any nose ports (just to make sure)
    for n = AllNosePorts
        n{1}.deactivate();
    end
    AllNosePorts = {};
    global arduinoConn
    fclose(arduinoConn);
    delete(arduinoConn);

    % prompt user to select directory to save pokeHistory
    global info
    global p h
    %if user chose to save the data
    if info.save == 1
        global pokeHistory stats sync_times
        stats.sync_times = sync_times;
        saveFolderName = info.folderName;
        % cd(folderName);
        currDay = datestr(date);
        %save pokeHistory and stats variables
        historyFile = fullfile(saveFolderName, strcat('pokeHistory',currDay,'.mat'));
        save(historyFile,'pokeHistory');
        statsFile = fullfile(saveFolderName, strcat('stats',currDay,'.mat'));
        save(statsFile,'stats');
        figHandles = findobj('Type','figure');
        % now that we have multiple figures (ie. the gui) we need to loop
        % through all the figure handles, find the one that is that stats fig,
        % and save it to the current directory.
        for i = 1:size(figHandles,1)
            if strcmpi('Stats Figure',figHandles(i).Name)
                statsFigFile = fullfile(saveFolderName, 'stats.fig');
                savefig(figHandles(i), statsFigFile);
            end
        end
       %properly formats the parameters and saves them in the same format as
       %the log
        parameters = strcat(info.mouseName,'_parameters');
        baseName = [parameters, '_', int2str(yyyymmdd(datetime)), '_'];
        fileCounter = 1;
        paramFileName = fullfile(saveFolderName, [baseName, int2str(fileCounter), '.mat']);
        while (exist(paramFileName, 'file'))
            fileCounter = fileCounter + 1;
            paramFileName = fullfile(saveFolderName, [baseName, int2str(fileCounter), '.mat']);
        end
        save(paramFileName,'p');
    end
    close 'Stats Figure'
end

