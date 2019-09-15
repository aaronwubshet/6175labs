import Multiplexer::*;


function Bit#(32) barrelShifterRight(Bit#(32) in, Bit#(5) shiftBy);
	for (Integer i = 0; i < 5 ; i=i+1)
	begin
		let j =  (shiftBy[i] == 0 ? 0 :2**i);
		for (Integer k = 0; k <32 ; k= k+1)
		begin
			if (k<=31-j)
			begin
				in[k] = in[j + k];
			end
			else
			begin
				in[k] = 0;
			end				
		end
	end
	return in;
endfunction



