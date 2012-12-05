% RUNEXPERIMENT - run the main part of the experiment
%
% results = runexperiment(e,recordingStimuli,curScreen)
%
% returns a struct with information about how the experiment was run
% (also saved to a file results.mat)
%
% if recordingStimuli=1 (default 0), stimuli will be saved to
% image files (for making movies). This is very slow and should never
% be used with real experiments
%
% curScreen - which screen to use (default 0). With one monitor, 0 is
% the main screen. If there are two monitors, you may need to set this
% to 1 or 2 to use the appropriate monitor

function results = runexperiment(e,recordingStimuli,curScreen)

thedevices = fields(e.devices);
for k=1:length(thedevices)
    if isempty(e.devices.(thedevices{k}))
        error('You need to run setupdevices before running runexperiment, e.g. e = setupdevices(e);');
    end
end

% Read strings, labels, symbols (if they exist)
experimentdata = readResources(e);

if nargin<2 || isempty(recordingStimuli)
    experimentdata.recordingStimuli = 0;
else
    experimentdata.recordingStimuli = recordingStimuli;
end

if nargin<3 || isempty(curScreen)
    curScreen = 0;
end

if experimentdata.recordingStimuli
    if ~exist('screenshots','dir')
        mkdir('screenshots');
    end
end

% make sure we are using openGL
AssertOpenGL;
% make key names same on windows and OSX
KbName('UnifyKeyNames');

% Call GetSecs to make sure mex file is loaded
GetSecs;

% Read in the codes used
codes = messagecodes;
experimentdata.screenInfo.bckgnd = 0;

% Prepare staircases if appropriate
experimentdata = prepareStaircase(e,experimentdata,e.protocol);


% Put everything inside a giant "try" so that we can close the screen if it crashes
try
    if ~isempty(experimentdata.sounds)
        experimentdata.pahandle = PsychPortAudio('Open', [], [], 0, experimentdata.freq, experimentdata.nrchannels);
    end
    % Call psychtoolbox to open the screen (can take a while)
    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask','General','UseVirtualFramebuffer');
    
    if ~isempty(experimentdata.vr)
        % initialize Matlab OpenGL
        InitializeMatlabOpenGL(0,1);
        fprintf('Stereo mode is %d\n',experimentdata.vr.stereomode);
        [experimentdata.screenInfo.curWindow, experimentdata.screenInfo.screenRect] = PsychImaging('OpenWindow', curScreen, experimentdata.screenInfo.bckgnd,[],32, 2,experimentdata.vr.stereomode);
        % Do OpenGL setup (required once per experiment)
        experimentdata = setupvr(e,experimentdata);
    else
        % Instead of the "usual" version, use PsychImaging to prevent bug in
        % graphics driver / memory leak causing the program to crash
        % (see explanation in http://tech.groups.yahoo.com/group/psychtoolbox/message/11951 )
        [experimentdata.screenInfo.curWindow,experimentdata.screenInfo.screenRect] = PsychImaging('OpenWindow', curScreen, experimentdata.screenInfo.bckgnd,[],32, 2);
    end
    
    writetolog(e,'Opened window');
    
    experimentdata = readVisualResources(e,experimentdata);
    
    % Hide the cursor
    HideCursor;
    
    % Loop through the protocol
    currentTrial=1;
    while currentTrial <= numTrials(e)
        fprintf('Trial %d of %d\n',currentTrial,numTrials(e));
        writetolog(e,sprintf('Trial %d',currentTrial));
        thistrialprotocol = e.protocol.trial{currentTrial};
        
        % Each "trial" has four stages (note that some of them may do nothing for some types of trials)
        %
        % 1. Setting up - set up all variables, prepare optotrak, etc
        % 2. Wait to start the event, at this point you can optionally go back or forward or quit
        % 3. Do that actual event
        % 4. Give feedback
        
        % STAGE 1 - setup the trial
        thistrial = readTrialParameters(e,thistrialprotocol,experimentdata);
        writetolog(e,'Read trial parameters');
        thistrialrecording = thistrial.recording;
        
        % run the appropriate trial setup for this type of stimulus
        thistrial = setup(thistrial.thisstimulus,e,thistrial,experimentdata);
        writetolog(e,'Setup stimulus');
        
        if ~isnan(thistrialrecording)
            thistrial.recording = thistrialrecording;
        elseif isnan(thistrial.recording)
            thistrial.recording = 1;
        end
        
        if thistrial.recording && isempty(thistrial.filename)
            error('A filename must be specified when recording');
        end
        
        % This may be changed below
        thistrial.sampleWhenNotRecording=0;
        
        % Make any necessary changes to thistrial for the response (e.g. setting thistrial.sampleWhenNotRecording)
        thistrial = setup(thistrial.thisresponse,thistrial);
        
        % Make any necessary changes to thistrial for the start
        thistrial = setup(thistrial.thisstarttrial,thistrial);
        
        % Setup the recording devices, if appropriate
        if thistrial.recording
            e = setupRecording(e,[e.resultDir '/' thistrial.filename],thistrial.recordingTime + 5,experimentdata.screenInfo.curWindow);
        end
        
        % Run any actions before the trial starts. This is used for stimuli that just show something for an infinite
        % amount of  time until a key is pressed (e.g. showText or showImage)
        preStart(thistrial.thisstimulus,experimentdata,thistrial,1);
        DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,1);
        writetolog(e,'Ran prestart');
        
        % STAGE 2 - wait for start of trial (determined by starttrial)
        
        % In all cases, the keyboard should be checked (value return in keyCode) to allow quitting the program between trials
        
        
        writetolog(e,'Ran starttrial setup');
        % Do the actual waiting.
        % If we need to show the position, we need to turn on sampling (but not record yet)
        if thistrial.showPosition || thistrial.sampleWhenNotRecording
            thistrial = startSamplingWithoutRecording(e,thistrial);
        end
        started = 0;
        while started==0
            [started,keyCode] = hasStarted(thistrial.thisstarttrial,e,experimentdata);
            
            if thistrial.showPosition
                preStart(thistrial.thisstimulus,experimentdata,thistrial,0);
                DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
                [lastposition,thistrial, experimentdata] = showPosition(e,thistrial,experimentdata,-1);
                Screen('Flip',experimentdata.screenInfo.curWindow,1);
            end
            if find(keyCode,1)==KbName('q') % q = quit
                if thistrial.showPosition || thistrial.sampleWhenNotRecording
                    stopRecording(e);
                end
                currentTrial = inf;
                writetolog(e,'Pressed q, quitting');
                break;
            end
        end
        % If the trial has recordingTime of 0 (i.e. just show something), then make sure they have left the key
        % before continuing
        if thistrial.recordingTime==0
            while hasStarted(thistrial.thisstarttrial,e,experimentdata)
                %    ; % wait for them to release the button
            end
        end
        
        % Check if keypress is 'q' to quit, 'n' to skip to next event, 'p' for previous event
        % (otherwise ignore)
        
        if find(keyCode)==KbName('n') % n = skip to next event
            currentTrial = currentTrial + 1;
            writetolog(e,'Pressed n, skipping to next event');
            continue;
        elseif find(keyCode)==KbName('p') % p = go back to previous event
            if currentTrial>1
                currentTrial = currentTrial-1;
                writetolog(e,'Pressed p, going back to previous event');
                continue;
            end
        elseif find(keyCode)==KbName('q') % q = quit
            currentTrial = inf;
            writetolog(e,'Pressed q, quitting');
            continue;
        end
        
        % Otherwise, continue!
        
        % STAGE 3- do the actual event
        % setup any triggers for later (e.g. for triggering EMG recordings, or TMS pulses)
        [triggerSent,triggerTime,triggerOffTime] = setupTrigger(thistrial);
        
        % setup any beeps
        thistrial = setupBeeps(thistrial);
        
        DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
        
        % Show the position (e.g. mouse, cursor) if appropriate
        if thistrial.showPosition
            [lastposition,thistrial, experimentdata] = showPosition(e,thistrial,experimentdata,-1);
        end
        Screen('Flip',experimentdata.screenInfo.curWindow,1);
        
        % Start recording with the devices
        if thistrial.recording
            startRecording(e,thistrial.filename,thistrial.recordingTime + 2);
        elseif thistrial.sampleWhenNotRecording
            startSamplingWithoutRecording(e,thistrial);
        end
        if thistrial.showPosition
            thistrial.lastx = []; thistrial.lasty = [];
        end
        
        
        if thistrial.waitTimeBefore > 0
            % Draw a fixation point, if appropriate
            if thistrial.drawFixation
                drawFixation(experimentdata);
            end
            DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
            if thistrial.showPosition
                [lastposition,thistrial] = showPosition(e,thistrial,experimentdata,-1);
            end
            Screen('Flip',experimentdata.screenInfo.curWindow,1);
            aborted=0;
            startFixation = GetSecs;
            while(GetSecs<startFixation+thistrial.waitTimeBefore)
                % In the button press cases, they should be still pressing
                % the button, otherwise abort and repeat the trial
                % (because the stimuli has not yet been shown)
                if ~stillAtStart(thistrial.thisstarttrial,e)
                    responseText = experimentdata.texts.TOO_EARLY;
                    drawText(experimentdata.screenInfo,'Courier',100,0,responseText);
                    writetolog(e,sprintf('Wrote text %s',responseText));
                    if thistrial.recording || thistrial.sampleWhenNotRecording || thistrial.showPosition
                        stopRecording(e);
                    end
                    if ispc
                        wavplay(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
                    else
                        audioplayer(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
                    end
                    WaitSecs(2);
                    DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,1);
                    aborted=1;
                    thistrial.aborted=1;
                    break;
                end
                if thistrial.drawFixation
                    drawFixation(experimentdata);
                end
                DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
                if thistrial.showPosition
                    [lastposition,thistrial] = showPosition(e,thistrial,experimentdata,-1);
                end
                Screen('Flip',experimentdata.screenInfo.curWindow,1);
            end
            if aborted
                continue;
            end
        end
        
        if isnan(experimentdata.framerate)
            thistrial.numFrames = round((thistrial.recordingTime - thistrial.waitTimeBefore)*experimentdata.screenInfo.monRefresh);
        else
            thistrial.numFrames = round((thistrial.recordingTime - thistrial.waitTimeBefore)*experimentdata.framerate);
        end
        if thistrial.numFrames < inf
            thistrial.frameInfo.startFrame = NaN * ones(thistrial.numFrames,1);
        end
        
        % run the appropriate start of trial setup. These files (e.g. startEvent.m) should be in the appropriate directories if
        % needed. For most stimuli types, it is not needed, and so the default (from @stimulus) will be run which does nothing
        [thistrial,experimentdata] = startEvent(thistrial.thisstimulus,thistrial,experimentdata,codes);
        
        abortTrial=0;
        for frame = 1:min(thistrial.numFrames,10^8)
            thistrial.frameInfo.startFrame(frame) = GetSecs;
            lastposition = [];
            if frame>1
                thisFrameTime = thistrial.frameInfo.startFrame(frame) - thistrial.frameInfo.startFrame(1);
            else
                thisFrameTime = 0;
                if thistrial.recording
                    markEvent(e,codes.firstFrame);
                end
            end
            if frame==thistrial.stimuliFrames
                if thistrial.recording
                    markEvent(e,codes.lastFrame);
                end
            end
            % send pulse at the appropriate time
            [triggerSent,thistrial.frameInfo] = ...
                checkTriggers(thistrial.frameInfo,triggerSent,triggerTime,triggerOffTime,thisFrameTime,thistrial.blockcounter,e);
            
            % beep if appropriate
            if any(~thistrial.beeped)
                for m=1:numel(thistrial.beep)
                    if ~thistrial.beeped(m) && thisFrameTime > thistrial.beep{m}.time
                        if thistrial.recording
                            markEvent(e,codes.beeped);
                        end
                        beep;
                        thistrial.beeped(m) = 1;
                    end
                end
            end
            
            % play a sound if appropriate
            for m=1:numel(thistrial.playAudioFile)
                if ~thistrial.playAudioFile{m}.started && thisFrameTime > thistrial.playAudioFile{m}.starttime
                    PsychPortAudio('FillBuffer',experimentdata.pahandle,experimentdata.audioBuffer(thistrial.playAudioFile{m}.number));
                    PsychPortAudio('Start', experimentdata.pahandle, [], 0, 0);
                    thistrial.playAudioFile{m}.started = GetSecs;
                    markEvent(e,codes.soundPlayed);
                end
            end
            
            % Check if they have started moving already
            if thistrial.checkMoving && thisFrameTime >= thistrial.checkMoving
                % If they are still pressing the button, abort
                if stillPressing(thistrial.thisstarttrial,e,experimentdata)
                    DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
                    responseText = experimentdata.texts.TOO_LATE;
                    drawText(experimentdata.screenInfo,'Courier',100,0,responseText);
                    writetolog(e,sprintf('Wrote text %s',responseText));
                    if ispc
                        wavplay(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
                    else
                        audioplayer(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
                    end
                    WaitSecs(1);
                    DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,1);
                    abortTrial = 1;
                    break;
                else
                    % don't check again this trial
                    thistrial.checkMoving=0;
                end
            end
            
            if frame <= thistrial.stimuliFrames
                % Present a frame
                DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
                % run the appropriate trial. This files (e.g. frame.m) should be in e.g. @videostimulus
                % If the file is absent, the default from @stimulus will be used (which does nothing)
                [thistrial,experimentdata,breakfromloop,thistrial.thisstimulus] = displayFrame(thistrial.thisstimulus,e,frame,thistrial,experimentdata);
                if thistrial.showPosition
                    [lastposition,thistrial,experimentdata] = showPosition(e,thistrial,experimentdata,frame);
                end

                if breakfromloop
                    break;
                end
                
                % if a framerate has been set, set the next flip to
                % be at the appropriate time (otherwise, as fast as possible)
                if ~isnan(experimentdata.framerate) && frame > 1
                    % Set it to 90% of the time (it needs to be slightly before the desired time)
                    nextflip = thistrial.VBLTimestamp(frame-1) + 0.9 * (1/experimentdata.framerate);
                else
                    nextflip = 0;
                end
                
                [thistrial.VBLTimestamp(frame) thistrial.StimulusOnsetTime(frame) ...
                    thistrial.FlipTimestamp(frame) thistrial.Missed(frame) ...
                    thistrial.Beampos(frame)] = ...
                    Screen('Flip',experimentdata.screenInfo.curWindow,nextflip,thistrial.dontclear);
            else
                % Pass time until the end of the trial (so there will be the right number of frames)
                DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
                if thistrial.showPosition
                    [lastposition,thistrial] = showPosition(e,thistrial,experimentdata,frame);
                end
                Screen('Flip',experimentdata.screenInfo.curWindow,0,0);
            end
            % check if the trial should be ended
            if ~isempty(lastposition)
                [tofinish,thistrial,experimentdata] = finishTrial(thistrial.thisresponse,thistrial,experimentdata,e,lastposition);
            else
                [tofinish,thistrial,experimentdata] = finishTrial(thistrial.thisresponse,thistrial,experimentdata,e);
            end
            if tofinish
                break;
            end
        end
        if abortTrial
            DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,1);
            % Stop recording
            if thistrial.recording || thistrial.sampleWhenNotRecording || thistrial.showPosition
                stopRecording(e);
            end
            while stillPressing(thistrial.thisstarttrial,e,experimentdata)
                %    ; % wait for them to release the button
            end
            continue;
        end
        % Clear the screen
        DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,1);
        
        % Stop recording
        % Save the file later (after feedback) because it can be slow
        if thistrial.recording || thistrial.sampleWhenNotRecording || thistrial.showPosition
            stopRecording(e);
        end
        % Give feedback if recording has taken place
        if thistrial.recording
            dataSummary = getDataSummary(e);
            if currentTrial>1
                thistrial = feedback(thistrial.thisresponse,e,thistrial,results.thistrial{currentTrial-1},experimentdata,dataSummary);
            else
                thistrial = feedback(thistrial.thisresponse,e,thistrial,[],experimentdata,dataSummary);
            end
        else
            dataSummary = NaN;
        end
        
        DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
        
        if thistrial.textFeedback==1 && isfield(thistrial,'responseText')
            if ~thistrial.textFeedbackShowBackground
                Screen('Flip',experimentdata.screenInfo.curWindow,0,0);
            end
            drawText(experimentdata.screenInfo,'Courier',100,0,thistrial.responseText);
            WaitSecs(1);
            writetolog(e,sprintf('Wrote text %s',thistrial.responseText));
        end
        if thistrial.playsound && thistrial.auditoryFeedback
            if ispc
                wavplay(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
            else
                audioplayer(experimentdata.annoyingBeep,experimentdata.annoyingBeepf);
            end
            WaitSecs(2);
        end
        
        experimentdata = updateStaircase(e,experimentdata);
        
        DrawBackground(experimentdata.screenInfo,thistrial,experimentdata.boxes,experimentdata.labels,0);
        
        % Save the file
        if isfield(thistrial,'filename') && thistrial.recording
            saveFile(e);
        end
        % Save thistrial
        results.thistrial{currentTrial} = thistrial;
        if isfield(thistrial,'successful')
            experimentdata.successful(currentTrial) = thistrial.successful;
        end
        if isstruct(dataSummary) && isfield(dataSummary,'RT')
            % include some other useful data
            thistrial.RT = dataSummary.RT;
            experimentdata.RTs(currentTrial) = dataSummary.RT;
        elseif isstruct(dataSummary) && isfield(dataSummary,'kb_RT')
            thistrial.RT = dataSummary.kb_RT;
            experimentdata.RTs(currentTrial) = dataSummary.kb_RT;
        end
        if isfield(thistrial,'percentCoherent')
            experimentdata.percentCoherents(currentTrial) = str2double(thistrial.percentCoherent);
        end
        if isfield(thistrial,'noiseVar')
            experimentdata.noiseLevels(currentTrial) = noiseVar;
        end
        if ~isempty(thistrial.filename)
            trialinfofilename = [e.resultDir '/trialinfo_' thistrial.filename '.mat'];
            save(trialinfofilename,'thistrial');
            writetolog(e,sprintf('Saved dot/frame data to file %s',trialinfofilename));
        end
        
        % Check that the recording was OK
        if thistrial.recording && thistrial.checkRecording
            checkRecording(e,dataSummary,experimentdata,thistrial);
        end
        
        % any post-trial cleanup for the stimulus
        [thistrial,experimentdata] = postTrial(thistrial.thisstimulus,dataSummary,thistrial,experimentdata);
        
        % Write screenshots to disk, if appropriate
        if experimentdata.recordingStimuli
            for k=1:length(thistrial.imageArray)
                imwrite(thistrial.imageArray{k},sprintf('screenshots/trial%03dframe%03d.jpg',currentTrial,k));
            end
        end
        
        currentTrial = currentTrial+1;
        
        % If they are pressing the 'q' key, then quit
        [keyCode,keyCode,keyCode] = KbCheck;
        if find(keyCode,1)==KbName('q') % q = quit
            currentTrial = inf;
            writetolog(e,'Pressed q, quitting');
            continue;
        end
    end
    
    % Set the screen back to normal
    closescreen;
    if ~isempty(experimentdata.sounds)
        PsychPortAudio('Close');
    end
    if exist('experimentdata','var')
        results.experimentdata = experimentdata;
    end
    % Save the overall results struct
    if exist('results','var')
        resultfilename = [e.resultDir '/results.mat'];
        save(resultfilename,'results');
        writetolog(e,sprintf('Saved result data to file %s',resultfilename));
    else
        results = [];
    end
catch err
    fprintf('Caught an error\n');
    fprintf('Error caught on line %d in %s: \n %s \n',err.stack(1).line,err.stack(1).file,err.message);
    
    % save current data
    if exist('experimentdata','var')
        results.experimentdata = experimentdata;
    end
    % Save the overall results struct
    resultfilename = [e.resultDir '/results.mat'];
    if exist('results','var')
        save(resultfilename,'results');
        writetolog(e,sprintf('Saved result data to file %s',resultfilename));
    else
        writetolog(e,sprintf('No variable results to write to file'));
    end
    closescreen;
end