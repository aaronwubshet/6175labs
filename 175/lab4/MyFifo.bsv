import Ehr::*;
import Vector::*;

//////////////////
// Fifo interface 

interface Fifo#(numeric type n, type t);
    method Bool notFull;
    method Action enq(t x);
    method Bool notEmpty;
    method Action deq;
    method t first;
    method Action clear;
endinterface

/////////////////
// Conflict FIFO

module mkMyConflictFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Reg#(Bit#(TLog#(n)))    enqP     <- mkReg(0);
    Reg#(Bit#(TLog#(n)))    deqP     <- mkReg(0);
    Reg#(Bool)              empty    <- mkReg(True);
    Reg#(Bool)              full     <- mkReg(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);
	method Bool notFull;
		return !full;
	endmethod
	
	method Action enq(t x) if(!full);
		if (enqP==max_index)
		begin
			enqP <= 0;
			if (deqP == 0)
				full <= True;
		end	
		else
		begin
			enqP <= enqP + 1;
		end
		data[enqP] <= x;
		empty <= False;
		if (enqP+1 == deqP)
			full <= True;
	endmethod

	method Bool notEmpty;
		return !empty;
	endmethod

	method Action deq if(!empty);
		if (deqP == max_index)
		begin
			deqP <= 0;
			if ( enqP == 0)
				empty <= True;
		end	
		else
		begin
			deqP <= deqP +1;
		end
		full <= False;
		if (deqP+1 == enqP)
			empty <= True;
	endmethod

	method t first if(!empty);
		return data[deqP];
	endmethod

	method Action clear;
		enqP <= 0;
		deqP <= 0;
		full <= False;
		empty <= True;
	endmethod

    // TODO: Implement all the methods for this module
endmodule

/////////////////
// Pipeline FIFO

// Intended schedule:
//      {notEmpty, first, deq} < {notFull, enq} < clear
module mkMyPipelineFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
 
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(3, Bit#(TLog#(n)))    enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n)))    deqP     <- mkEhr(0);
    Ehr#(3, Bool)              empty    <- mkEhr(True);
    Ehr#(3, Bool)              full     <- mkEhr(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);
	method Bool notFull;
		return !full[1];
	endmethod
	
	method Action enq(t x) if(!full[1]);
		if (enqP[1]==max_index)
		begin
			enqP[1] <= 0;
			if (deqP[1] == 0)
				full[1] <= True;
		end	
		else
		begin
			enqP[1] <= enqP[1] + 1;
		end
		data[enqP[1]] <= x;
		empty[1] <= False;
		if (enqP[1]+1 == deqP[1])
			full[1] <= True;
	endmethod

	method Bool notEmpty;
		return !empty[0];
	endmethod

	method Action deq if(!empty[0]);
		if (deqP[0] == max_index)
		begin
			deqP[0] <= 0;
			if ( enqP[0] == 0)
				empty[0] <= True;
		end	
		else
		begin
			deqP[0] <= deqP[0] +1;
		end
		full[0] <= False;
		if (deqP[0]+1 == enqP[0])
			empty[0] <= True;
	endmethod

	method t first if(!empty[0]);
		return data[deqP[0]];
	endmethod

	method Action clear;
		enqP[2] <= 0;
		deqP[2] <= 0;
		full[2] <= False;
		empty[2] <= True;
	endmethod


		
endmodule

//////////////
// Bypass FIFO

// Intended schedule:
//      {notFull, enq} < {notEmpty, first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo


 
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(3, Bit#(TLog#(n)))    enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n)))    deqP     <- mkEhr(0);
    Ehr#(3, Bool)              empty    <- mkEhr(True);
    Ehr#(3, Bool)              full     <- mkEhr(False);

    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);
	method Bool notFull;
		return !full[0];
	endmethod
	
	method Action enq(t x) if(!full[0]);
		if (enqP[0]==max_index)
		begin
			enqP[0] <= 0;
			if (deqP[0] == 0)
				full[0] <= True;
		end	
		else
		begin
			enqP[0] <= enqP[0] + 1;
		end
		data[enqP[0]] <= x;
		empty[0] <= False;
		if (enqP[0]+1 == deqP[0])
			full[0] <= True;
	endmethod

	method Bool notEmpty;
		return !empty[1];
	endmethod

	method Action deq if(!empty[1]);
		if (deqP[1] == max_index)
		begin
			deqP[1] <= 0;
			if ( enqP[1] == 0)
				empty[1] <= True;
		end	
		else
		begin
			deqP[1] <= deqP[1] +1;
		end
		full[1] <= False;
		if (deqP[1]+1 == enqP[1])
			empty[1] <= True;
	endmethod

	method t first if(!empty[1]);
		return data[deqP[1]];
	endmethod

	method Action clear;
		enqP[2] <= 0;
		deqP[2] <= 0;
		full[2] <= False;
		empty[2] <= True;
	endmethod


		
endmodule

//////////////////////
// Conflict-free fifo

// Intended schedule:
//      {notFull, enq} CF {notEmpty, first, deq}
//      {notFull, enq, notEmpty, first, deq} < clear
module mkMyCFFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo


    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Reg#(Bit#(TLog#(n)))    enqP     <- mkReg(0);
    Reg#(Bit#(TLog#(n)))    deqP     <- mkReg(0);
    Reg#(Bool)              empty    <- mkReg(True);
    Reg#(Bool)              full     <- mkReg(False);
	Ehr#(2, Maybe#(t))		enqCalled <- mkEhr(Invalid);
	Ehr#(2, Bool)			deqCalled <- mkEhr(False);
	Ehr#(2, Bool)			clearCalled <- mkEhr(False);
    // useful value
    Bit#(TLog#(n))          max_index = fromInteger(valueOf(n)-1);


	(* no_implicit_conditions, fire_when_enabled*)
	rule canonicalize;

		if (isValid(enqCalled[1]) && !clearCalled[1])
		begin
			if (enqP == max_index)
			begin
				enqP <= 0;
				if (deqP == 0&& !deqCalled[1])
					full <= True;
			end	
			else
			begin
				enqP <= enqP + 1;
			end
			data[enqP] <= fromMaybe(?, enqCalled[1]);
			empty <= False;
			
			if (enqP+1 == deqP&&!deqCalled[1])
				full <= True;
		end

		if (deqCalled[1]&& !clearCalled[1] )
		begin
			if (deqP == max_index)
			begin
				deqP <= 0;
				if ( enqP == 0&&!isValid(enqCalled[1]))
					empty <= True;
			end	
			else
			begin
				deqP <= deqP +1;
			end
			full <= False;
			
			if (deqP+1 == enqP&&!isValid(enqCalled[1]))
				empty <= True;
			
		end
		if (clearCalled[1])
		begin
			
			enqP <= 0;
			deqP <= 0;
			full <= False;
			empty <= True;
		end
	
		clearCalled[1] <= False;
		deqCalled[1] <= False;
		enqCalled[1] <= tagged Invalid;
	endrule	
	method Bool notFull;
		return !full;
	endmethod
	
	method Action enq(t x) if(!full);
		enqCalled[0] <= tagged Valid x;
	endmethod

	method Bool notEmpty;
		return !empty;
	endmethod

	method Action deq if(!empty);
		deqCalled[0] <= True;
	endmethod

	method t first if(!empty);
		return data[deqP];
	endmethod

	method Action clear;
		clearCalled[0] <= True;		
	endmethod


endmodule

