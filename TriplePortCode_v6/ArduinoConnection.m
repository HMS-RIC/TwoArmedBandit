%% ArduinoConnetion: serial port connection to an Arduino
classdef ArduinoConnection < handle

properties
	debugMode = false;
	connected = false;
	batchMode = false;
	serialConnection = [];
	batchMessageString = '';
	messgeCallbackFcn = [];
	handshakeCharacter = '^';
end

methods
	function obj = ArduinoConnection(messgeCallbackFcn, baudRate)
		obj.messgeCallbackFcn = messgeCallbackFcn;
		obj.batchMessageString = '';
		arduinoPortName = obj.findFirstArduinoPort();

		if isempty(arduinoPortName)
		    disp('Can''t find serial port with Arduino')
		    return
		end

		% Define the serial port object.
		fprintf('Starting serial on port: %s\n', arduinoPortName);
		serialPort = serial(arduinoPortName);

		% Set the baud rate
		serialPort.BaudRate = 9600;
		if (nargin >= 2)
			serialPort.BaudRate = baudRate;
		end

		% Add a callback function to be executed whenever 1 line is available
		% to be read from the port's buffer.
		serialPort.BytesAvailableFcn = @(port, event)obj.readMessage(port, event);
		serialPort.BytesAvailableFcnMode = 'terminator';
        serialPort.Terminator = 'CR/LF'; % Ardunio println() commands uses CR/LN termination

		% Open the serial port for reading and writing.
		obj.serialConnection = serialPort;
		fopen(serialPort);

		% wait for Arduino handshake
		% (we write an '^' to the Arduino and expect an '^' in return)
		fprintf('Waiting for Arduino startup')
        obj.writeString(obj.handshakeCharacter)
        waitCounter = 0;
	    pause(0.2);
		while (~obj.connected)
            waitCounter = waitCounter + 1;
            obj.writeString(obj.handshakeCharacter)
		    pause(0.2);
            if (mod(waitCounter,5)==0)
			    fprintf('.');
            end
		end
		fprintf('\n')
	end

	function startBatchMessage(obj)
		obj.batchMode = true;
		obj.batchMessageString = '';
	end

	function sendBatchMessage(obj)
		obj.batchMode = false;
		obj.writeString(obj.batchMessageString);
		obj.batchMessageString = '';
	end


	function writeMessage(obj, messageChar, arg1, arg2)
		% Will format the message and send to the Arduino
		% Unless in batchMode: then it will append foramtted message to the batch message string
		if (nargin == 2)
		    stringToSend = sprintf('%s',messageChar);
		elseif (nargin == 3)
		    stringToSend = sprintf('%s %d',messageChar, arg1);
		else
		    stringToSend = sprintf('%s %d %d',messageChar, arg1, arg2);
		end

		if obj.batchMode
			if isempty(obj.batchMessageString)
				obj.batchMessageString = stringToSend;
			else
				obj.batchMessageString = sprintf('%s; %s', obj.batchMessageString, stringToSend);
			end
		else
		    obj.writeString(stringToSend);
		end
	end

	function writeString(obj, stringToWrite)
	    fprintf(obj.serialConnection,'%s\n',stringToWrite, 'sync');

	    % DEBUGING
	    if obj.debugMode
	    	disp(['To Arduino: "', stringToWrite, '"' ]);
	    end
	end

	function readMessage(obj, port, event)
		% read line from serial buffer
	   	receivedMessage = fgetl(obj.serialConnection);
	   	%fprintf('#%s#\n',receivedMessage);
	   	% fprintf('--> "');
	   	% [tline,count,msg] = fgetl(obj.serialConnection);
	   	% fprintf('%s" :: %d :: "%s" \n', tline,count,msg);

		% we confirm that the connection was established once the first message is recieved
		if (~obj.connected)
			obj.connected = true;
		end

	    % DEBUGING
	    if obj.debugMode
	    	disp(['From Arduino: "', receivedMessage, '"' ]);
	    end

		% run user code to evaluate the message
        %feval(obj.messgeCallbackFcn, receivedMessage);
        obj.messgeCallbackFcn(receivedMessage);

	end

	function fclose(obj)
		try
			fclose(obj.serialConnection);
        end
        obj.serialConnection = [];
        % delete(obj.serialConnection)
        %clear obj.serialConnection
	end

	function delete(obj)
		obj.fclose();
	end

end

methods (Static)

	function port = findFirstArduinoPort()
		% finds the first port with an Arduino on it.

		serialInfo = instrhwinfo('serial');
		archstr = computer('arch');

		port = [];

		% OSX code:
		if strcmp(archstr,'maci64')
		    for portN = 1:length(serialInfo.AvailableSerialPorts)
		        portName = serialInfo.AvailableSerialPorts{portN};
		        if strfind(portName,'tty.usbmodem')
		            port = portName;
		            return
		        end
		    end
		else
		% PC code:
		    % code from Benjamin Avants on Matlab Answers
		    % http://www.mathworks.com/matlabcentral/answers/110249-how-can-i-identify-com-port-devices-on-windows

		    Skey = 'HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM';
		    % Find connected serial devices and clean up the output
		    [~, list] = dos(['REG QUERY ' Skey]);
		    list = strread(list,'%s','delimiter',' ');
		    coms = 0;
		    for i = 1:numel(list)
		      if strcmp(list{i}(1:3),'COM')
		            if ~iscell(coms)
		                coms = list(i);
		            else
		                coms{end+1} = list{i};
		            end
		        end
		    end
		    key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\';
		    % Find all installed USB devices entries and clean up the output
		    [~, vals] = dos(['REG QUERY ' key ' /s /f "FriendlyName" /t "REG_SZ"']);
		    vals = textscan(vals,'%s','delimiter','\t');
		    vals = cat(1,vals{:});
		    out = 0;
		    % Find all friendly name property entries
		    for i = 1:numel(vals)
		        if strcmp(vals{i}(1:min(12,end)),'FriendlyName')
		            if ~iscell(out)
		                out = vals(i);
		            else
		                out{end+1} = vals{i};
		            end
		        end
		    end
		    % Compare friendly name entries with connected ports and generate output
		    for i = 1:numel(coms)
		        match = strfind(out,[coms{i},')']);
		        ind = 0;
		        for j = 1:numel(match)
		            if ~isempty(match{j})
		                ind = j;
		            end
		        end
		        if ind ~= 0
		            com = str2double(coms{i}(4:end));
		            % Trim the trailing ' (COM##)' from the friendly name - works on ports from 1 to 99
		            if com > 9
		                len = 8;
		            else
		                len = 7;
		            end
		            devs{i,1} = out{ind}(27:end-len);
		            devs{i,2} = coms{i};
		        end
		    end
		    % get the first arduino port
		    for i = 1:numel(coms)
		        [portFriendlyName, portName] = devs{i,:};
		        if strfind(portFriendlyName, 'Arduino')
		            port = portName;
		            return
		        elseif strfind(portFriendlyName, 'Teensy')
		            port = portName;
		            return
		        end
		    end
		end
	end



end
end
