function logValue(valName, value)
    global logFileID
    timestamp = datestr(clock,'dd-mmm-yyyy HH:MM:SS.FFF'); % include fractional seconds in timestamp
    if isnumeric(value)
        value = num2str(value);
    end
    fprintf(logFileID, '%s, %s, %s\n', timestamp , valName, value); 

    % DEBUGGING:
    global printLogToCommandLine
    if printLogToCommandLine
        if value
            disp([valName,': ', value])
        else
            disp(valName)
        end
    end
end
