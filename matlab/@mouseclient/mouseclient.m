% MOUSECLIENT - create an object to connect to the mouse server and send commands to it 
%
% mc = mouseclient(server,port,maxx,maxy,experiment,debug)
% server is the server to connect to (for this machine, use 'localhost')
% port is the TCP/IP port to connect on
% experiment is a pointer to the parent object (which must have a
% function called "writetolog",e.g. writetolog(experiment,'Message');
% If debug=1, then the client will print more messages
%
% maxx, maxy are the screen resolution, so that getsample will provide 
% the mouse position in the range 0-1
%
% This class requires that "MSocket" be in the path. The program is
% available from http://code.google.com/p/msocket/downloads/list

function [mc,params] = mouseclient(inputParams,experiment,debug)

params.name = {'maxx','maxy'};
params.type = {'number','number'};
params.description = {'Maximum x coordinate on the screen (i.e. horizontal screen width in pixels)',...
    'Maximum y coordinate on the screen (i.e. vertical screen height in pixels)'};
params.required = [1 1];
params.default = {0,0};
params.classdescription = 'Connect to the mouse server to sample the mouse location';
params.classname = 'mouse';
params.parentclassname = 'socketclient';

if nargout>1
    mc = [];
    return;
end

[mc,mcParent] = readParameters(params,inputParams);
   
mc = class(mc,'mouseclient',socketclient(mcParent,experiment,debug));
