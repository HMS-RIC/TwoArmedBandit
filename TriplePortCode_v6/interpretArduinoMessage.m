
function interpretArduinoMessage(messageString)
global arduinoConnection newPortID
global AllNosePorts

%fprintf('#%s#\n',messageString);
messageString = strtrim(messageString);
%fprintf('##%s##\n',messageString);

messageType = messageString(1);
portNum = [];
if length(messageString) > 1
    portNum = str2num(messageString(2:end));
end

switch messageType
    case '^'
        % Arduino startup
        if (arduinoConnection == 0)
            arduinoConnection = 1;
            logEvent('Arduino connection established');
        else
            global ArduinoSyncFunc
            if isa(ArduinoSyncFunc,'function_handle')
                feval(ArduinoSyncFunc);
            end
        end
    case 'N'
        % New poke initialized
        newPortID = portNum;
        logValue('New poke initialized',portNum);
    case 'I'
        % Nose in (unrewarded)
        logValue('Nose in', portNum);
        noseIn = 1;
        AllNosePorts{portNum}.noseIn();
        %lastPokeTime = clock;
    case 'D'
        % Rewarded Nose in (rewarded)
        logValue('Nose in', portNum);
        noseIn = 1;
        logValue('Reward delivered', portNum);
        AllNosePorts{portNum}.rewardedNoseIn();
        %lastPokeTime = clock;
    case 'O'
        % Nose out
        logValue('Nose out', portNum);
        noseIn = 0;
        AllNosePorts{portNum}.noseOut();
    case 'R'
        % Standalone reward
        logValue('Manual Reward delivered', portNum);
        AllNosePorts{portNum}.manualReward();
        %rewardArray = [rewardArray, 1];

    case 'L'
        % Laser stim started
        logValue('Laser on', portNum);
        AllNosePorts{portNum}.laserOn();
    case 'l'
        % Laser stim ended
        logValue('Laser off', portNum);
        AllNosePorts{portNum}.laserOff();
    case 'T'
        % Laser stim timeout
        logValue('Laser timeout', portNum);
        warning('Laser timeout. Make sure "Max laser stim duration" is set appropriately.');


    case '#'
        % Error
        logEvent('Arduino ERROR');
        fprintf('\nERROR: Arduino error code: [%s]\n\n', messageString);
        warning('Arduino error');
    otherwise
        % unknown input
        disp(messageType)
        logValue('Unknown input from Arduino',messageString);
end
