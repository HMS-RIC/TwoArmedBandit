function setupLogging(logName)
    global logFileID
    global info
    PathName = info.folderName;
    baseName = [logName, '_', int2str(yyyymmdd(datetime)), '_'];
    fileCounter = 1;
    fName = [baseName, int2str(fileCounter), '.csv'];
    while (exist(fullfile(PathName,fName), 'file'))
        fileCounter = fileCounter + 1;
        fName = [baseName, int2str(fileCounter), '.csv'];
    end
    %gets FileName and PathName from info global struct (GUI)
    fullName = fullfile(PathName,fName);
    logFileID = fopen(fullName, 'w');
end
