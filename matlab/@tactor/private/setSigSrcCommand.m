% setSigSrcCommand - set the signal source (sin1 or sin2 or sin1+sin2)
%
% command = setSigSrcCommand(lownibble,highnibble)
%
% lownibble is for tactors 1-4
% highnibble is for tactor 5-8
%
% for each, 0: No Signal
%   		1: Signal from Primary sinewave generator
%	   	    2: Signal from Secondary sinewave generator
%		    3: Summed Signals from both sinewave generators

function command = SetSigSrcCommand(lownibble,highnibble)

PacketStartByte = uint8(2);
PacketEndByte = uint8(3);
MasterBoard = uint8(0);
setSigSrcCommand = uint8(hex2dec('15'));

DataLength = uint8(1);
value = uint8(lownibble * 16 + highnibble);

command = withChecksum([PacketStartByte MasterBoard setSigSrcCommand DataLength value PacketEndByte]);

