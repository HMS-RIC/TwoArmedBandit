function runTriplePortExperiment_laser_state(varargin)

    global arduinoConnection arduinoPort
    global arduinoMessageString
    global p % parameter structure
    global info % structure containing mouse name and folder to be saved in

    % Hard code center stim probability for now
    p.centerLaserStimProb = 0.5;

    %% Setup

    % cleanup routine to be executed even if this function is terminated early
    finishup = onCleanup(@triplePortCleanup);

    % seed random number generator (to prevent repeating the same values on
    % different experiments)
    rng('shuffle');

    %gets the mouse's name
    mouseName = info.mouseName;
    %creates the log file name
    mouseLog = strcat(mouseName,'_log');
    %sets up the logging for mouseLog
    setupLogging(mouseLog);


    %% log all paramters and inital values
    fn = fieldnames(p);
    for i=1:length(fn)
        fName = fn{i};
        logValue(fName,p.(fName));
    end
    rngState = rng;
    logValue('RNG Seed', rngState.Seed);
    logValue('RNG Type', rngState.Type);


    %% set up Arduino
    arduinoMessageString = '';
    clearPorts();
    arduinoPortNum = findArduinoPort();
    if ~arduinoPortNum
        disp('Can''t find serial port with Arduino')
        return
    end
    arduinoConnection = 0;
    arduinoPort = setupArduinoSerialPort(arduinoPortNum);
    % wait for Arduino startup
    fprintf('Waiting for Arduino startup')
    while (arduinoConnection == 0)
        fprintf('.');
        pause(0.5);
    end
    fprintf('\n')



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

    %for now let's hard code in the laser stim parameters:
    rightPort.setLaserDelay(0); %this is in milliseconds
    rightPort.setLaserStimDuration(10) %ms
    rightPort.setLaserPulseDuration(10) %ms
    rightPort.setLaserPulsePeriod(10) %ms

    leftPort.setLaserDelay(0); %this is in milliseconds
    leftPort.setLaserStimDuration(10) %ms
    leftPort.setLaserPulseDuration(10) %ms
    leftPort.setLaserPulsePeriod(10) %ms

    centerPort.setLaserDelay(0); %this is in milliseconds
    centerPort.setLaserStimDuration(500) %ms
    centerPort.setLaserPulseDuration(500) %ms
    centerPort.setLaserPulsePeriod(500) %ms

    %create NosePort specifically for syncing with imaging
    %this object simply receives 5 volt pulses from the inscopix box
    %on pin 11. IE it treats like a IR beam and when it is detected (when
    %a 5 volt pulse comes in) it records like a nose poke.
    syncPort = NosePort(11,13);
    syncPort.deactivate()
    syncPort.noseInFunc = @syncIn;
    logValue('Sync port ID', syncPort.portID);

    global sync_counter
    sync_counter = 0;

    if p.centerPokeTrigger
        rightPort.deactivate();
        leftPort.deactivate();
    else
        rightPort.activate();
        leftPort.activate();
    end


    %% run trials
    global numBlocks
    numBlocks = struct;
    numBlocks.left = 0;
    numBlocks.right = 0;
    if p.rightRewardProb >= p.leftRewardProb
        numBlocks.right = 1;
    else
        numBlocks.left = 1;
    end

    global currBlockReward blockRange currBlockSize
    currBlockReward = 0;
    blockRange = [p.blockRangeMin:p.blockRangeMax];
    currBlockSize = randi([min(blockRange),max(blockRange)]);
    display(currBlockSize)

    global pokeHistory pokeCount
    pokeCount = 0;
    pokeHistory= struct;

    global iti lastPokeTime
    iti = p.minInterTrialInterval;
    lastPokeTime = clock;

    %create stats structure for online analysis and visualization
    global stats
    % initialize the first entry of stats to be zeros
    stats = initializestats;
    cumstats = cumsumstats(stats);
    %create figure for onilne visualization
    global h
    h = initializestatsfig(cumstats);



    %% Set up Trial State Machine
    % Global variable TrialState will contain the name of the current state:
    %   'ITI'       Forced no-poke period. Every poke resets timer.
    %                   Transition to START when no-poke condition is met.
    %   'START'     Wait for center poke to initiate.
    %                   Transition to 'REWARD' upon center poke.
    %   'REWARD_WINDOW' Within the reward window. Side pokes get probabilistically rewarded.
    %                   Transition to 'ITI' upon any poke or timeout.
    %
    % To initiate a state transition call:
    %       stateTransitionEvent(<event>)
    % Where <event> is a poke/timeout/other even that might trigger a transition


    global TrialState = 'ITI';
    lastPokeTime = 0; % force immediate transition from ITI to START

    %% run the program.....
    % runs as long as info.running has not been set to false via the Stop
    % Experiment button
    while info.running
        pause(0.1)
        % actively probe whether or not enough time has elapsed to start a
        % new trial. If so, turn on the LED>
        if etime(clock, lastPokeTime) >= iti
            stateTransitionEvent('itiTimeout');
        end
    end
    triplePortCleanup();
end



%% stateTransitionEvent: transitions between states of the state machine
function newTrialState = stateTransitionEvent(eventName)
    global TrialState

    newTrialState = '';

    % 1) Respond to events based on the current state
    %
    switch TrialState
        case 'ITI'
            % wait for itiTimeout event before transitioning to START
            % reset timer on every poke
            % if in training mode (p.centerPokeTrigger == false),
            %   transition stright to REWARD_WINDOW
            switch eventName
                case {'centerPoke', 'leftPoke', 'rightPoke'}
                     logIncorrectPoke(eventName);
                case 'itiTimeout'
                    if (p.centerPokeTrigger)
                        newTrialState = 'START';
                    else
                        newTrialState = 'REWARD_WINDOW';
                    end
            end

        case 'START'
            % wait for central poke to transition to REWARD_WINDOW
            % side pokes result in transition to ITI state
            switch eventName
                case 'centerPoke'
                    newTrialState = 'REWARD_WINDOW';
                    logInitiationPoke(eventName);
                case {'leftPoke', 'rightPoke'}
                    logIncorrectPoke(eventName);
                    newTrialState = 'ITI';
            end

        case 'REWARD_WINDOW'
            switch eventName
                case 'rewardTimeout'
                    newTrialState = 'ITI';
                case 'centerPoke'
                    logIncorrectPoke(eventName);
                    newTrialState = 'ITI';
                case {'leftPoke', 'rightPoke'}
                    logDecisionPoke(eventName);
                    newTrialState = 'ITI';
            end

        otherwise
            warning('Unexpected state.')
    end

    % 2) State Transition
    if ~strcmp(newTrialState,'')
        TrialState = newTrialState;
    end

    % 3) Initialize new trial state (if needed)
    % Here is where we perform all initialization functions for a new
    % state that only need to be performed once, at the start of the
    % state (e.g., turning LEDs on/off).
    switch newTrialState
        case ''
            % didn't switch states; do nothing

        case 'ITI'
            TrialState = 'ITI';
            centerPort.ledOff();
            leftPort.ledOff();
            rightPort.ledOff();
            deactivateCenterLaserStim();
            deactivateSidePorts();

        case 'START'
            TrialState = 'START';
            centerPort.ledOn();
            leftPort.ledOff();
            rightPort.ledOff();
            activateCenterLaserStimWithProb(p.centerLaserStimProb);

        case 'REWARD_WINDOW'
            TrialState = 'REWARD_WINDOW';
            centerPort.ledOff();
            leftPort.ledOn();
            rightPort.ledOn();
            deactivateCenterLaserStim();
            activateLeft = (rand <= p.leftRewardProb); % activate left port with prob = p.leftRewardProb
            activateRight = (rand <= p.rightRewardProb); % activate right port with prob = p.rightRewardProb
            activateSidePorts(activateLeft, activateRight);
            activateSideLaserStimWithProb(p.laserstimprob);

        otherwise
            warning('Unexpected state.')
    end
end


%% Laser stim functions

function activateSideLaserStimWithProb(sideSitmProb)
    global rightPort leftPort laser_state
    if rand <= sideSitmProb
        rightPort.activateLaser();
        leftPort.activateLaser();
        laser_state = 1;
    else
        deactivateSideLaserStim();
    end
end

function deactivateSideLaserStim()
    global rightPort leftPort laser_state
    rightPort.deactivateLaser();
    leftPort.deactivateLaser();
    laser_state = 0;
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
    disp(sprintf('activateSidePorts:  R:%g  L:%g', activateRight, activateLeft));
    global rightPort leftPort

    % activate only the desired port(s)
    if activateRight
        rightPort.activate();
    end
    if activateLeft
        leftPort.activate();
    end
end

function deactivateSidePorts()
    disp('deactivateSidePorts')
    global rightPort leftPort deactivateTimer
    try
        stop(deactivateTimer)
    end
    rightPort.deactivate();
    leftPort.deactivate();
end

%% Nose In Functions
function syncIn(portID)
    disp('syncIn')
    % simply count the inscopix frames in a global variable.
    global sync_counter
    sync_counter = sync_counter + 1;
    global sync_times
    sync_times(sync_counter) = now;
end

function noseIn(portID)
    global rightPort leftPort centerPort
    disp('noseIn')

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
    global activateLeft activateRight laser_state center_laser_state
    global stats
    global iti
    global h

    global sync_counter sync_frame
    sync_frame = sync_counter;

    pokeCount = pokeCount+1; %increment pokeCount
    pokeHistory(pokeCount).timeStamp = now;
    timeSinceLastPoke = etime(clock, lastPokeTime);
    %update the lastPokeTime
    lastPokeTime = clock;

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
        pokeHistory(pokeCount).laser = laser_state;
        pokeHistory(pokeCount).laser = center_laser_state;
    end

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

    %in order to run update stats, we need a value for pokeHistory.REWARD
    pokeHistory(pokeCount).REWARD = 0; % this might be overwritten if reward happens

    %update stats and refresh figures
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
end


%% Reward Function
function rewardFunc(portID)
    disp('rewardFunc')
    global pokeHistory pokeCount stats sync_frame
    global h
    global currBlockReward

    currBlockReward = currBlockReward + 1;
    display(currBlockReward)

    % log rewarded port to poke history
    pokeHistory(pokeCount).REWARD = 1;
    %update stats and refresh figures
    stats = updatestats(stats,pokeHistory(pokeCount),pokeCount,sync_frame);
    cumstats = cumsumstats(stats);
    updatestatsfig(cumstats,h,pokeCount);
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
        display('Reward Probabilities Switched')
        display('Left Reward Prob:')
        p.leftRewardProb
        display('Right Reward Prob:')
        p.rightRewardProb
        display('Current Block Size:')
        global numBlocks
        if p.rightRewardProb >= p.leftRewardProb
            numBlocks.right = numBlocks.right + 1;
        else
            numBlocks.left = numBlocks.left + 1;
        end
        currBlockSize
    end
end


%% Cleanup
% Cleanup function is run when program ends (either naturally or after ctl-c)
function triplePortCleanup()
    disp('Cleaning up...')

    %turn all LEDs off
    global centerPort rightPort leftPort
    centerPort.ledOff();
    rightPort.ledOff();
    leftPort.ledOff();

    %close log file
    global logFileID AllNosePorts
    fclose(logFileID);

    %deactivate any nose ports (just to make sure)
    for n = AllNosePorts
        n{1}.deactivate();
    end
    AllNosePorts = {};
    clearPorts(); %clear nose ports

    % prompt user to select directory to save pokeHistory
    global info
    global p h
    %if user chose to save the data
    if info.save == 1
        global pokeHistory stats sync_times
        stats.sync_times = sync_times;
        folderName = info.folderName;
        cd(folderName);
        currDay = datestr(date);
        %save pokeHistory and stats variables
        save(strcat('pokeHistory',currDay,'.mat'),'pokeHistory');
        save(strcat('stats',currDay,'.mat'),'stats');
        figHandles = findobj('Type','figure');
        % now that we have multiple figures (ie. the gui) we need to loop
        % through all the figure handles, find the one that is that stats fig,
        % and save it to the current directory.
        for i = 1:size(figHandles,1)
            if strcmpi('Stats Figure',figHandles(i).Name)
                savefig(figHandles(i),'stats.fig');
            end
        end
       %properly formats the parameters and saves them in the same format as
       %the log
        parameters = strcat(info.mouseName,'_parameters');
        baseName = [parameters, '_', int2str(yyyymmdd(datetime)), '_'];
        fileCounter = 1;
        fName = [baseName, int2str(fileCounter), '.mat'];
        while (exist(fName, 'file'))
            fileCounter = fileCounter + 1;
            fName = [baseName, int2str(fileCounter), '.mat'];
        end
        save(fName,'p');
    end
    close 'Stats Figure'
end

