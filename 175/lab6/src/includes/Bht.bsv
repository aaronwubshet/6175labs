import Types::*;
import Vector::*;


interface DirectionPred#(numeric type numBits);
	method Addr ppcDP(Addr pc, Addr targetPC);
	method Action update(Addr pc, Bool taken);
	method Bit#(2) getDir(Addr pc);
endinterface

module mkBHT( DirectionPred#(numBits) );
	//number of BHT Entires
	Vector#(numBits, Reg#(Bit#(2))) bhtArr <- replicateM(mkReg(2'b01));
	
	function Bit#(numBits) getBhtIndex(Addr pc);
		return pc[valueof(numBits)+1:2];
	endfunction

	function Addr computeTarget (Addr pc, Addr targetPC, Bool taken);
		if(taken)
		begin
			return targetPC;
		end
		else
		begin
			return pc + 4;
		end
	endfunction
	
	function Bool extractDir(valueAtindex);
		Bool taken;
		if (valueAtindex == 2'b00 || valueAtindex == 2'b01)
		begin
			taken = False;
		end
		else
		begin
			taken = True;
		end
		return taken;
    endfunction

	function Bit#(2) getBhtEntry(index);
		return	bhtArr[index];
	endfunction

	function Bit#(2) newDpBits ( Bit#(2) dpBits, Bool taken);
		if(taken)
		begin
			if(dpBits == 2'b11)
			begin
				return 2'b11;
			end
			else if(dpBits == 2'b10)
			begin
				return 2'b11;
			end
			else if(dpBits == 2'b01)
			begin
				return 2'b10;
			end
			else
			begin
				return 2'b01;
			end
		end
		else
		begin
			if(dpBits == 2'b11)
			begin
				return 2'b10;
			end
			else if(dpBits == 2'b10)
			begin
				return 2'b01;
			end
			else if(dpBits == 2'b01)
			begin	
				return 2'b00;
			end
			else
			begin
				return 2'b00;
			end
		end
	endfunction

	method Bit#(2) getDir(Addr pc);
		let	idx = getBhtIndex(pc);
		return 	getBhtEntry(idx);
	endmethod

	method Addr ppcDP(Addr pc, Addr targetPC);
		Bit#(numBits) index = getBhtIndex(pc);
		let direction = extractDir(bhtArr[index]);
		return computeTarget(pc, targetPC, direction);
	endmethod
	
	method Action update(Addr pc, Bool taken);
		Bit#(numBits) index = getBhtIndex(pc);
		let dpBits = getBhtEntry(index);
		bhtArr[index] <= newDpBits(dpBits, taken);
	endmethod

endmodule
	
