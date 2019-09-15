import Ehr::*;
import Vector::*;
import FIFO::*;

interface Fifo#(numeric type n, type t);
    method Action enq(t x);
    method Action deq;
    method t first;
endinterface


module mkFifo(Fifo#(3,t)) provisos (Bits#(t,tSz));
   // define your own 3-elements fifo here. 
   Reg#(t) a <- mkRegU();
   Reg#(t) b <- mkRegU();
   Reg#(t) c <- mkRegU();
   Reg#(Bool) aState <- mkReg(False);
   Reg#(Bool) bState <- mkReg(False);
   Reg#(Bool) cState <- mkReg(False);
   method Action enq(t x) if (!aState||!bState||!cState);
	if (!cState)
	begin
		cState <= True;
		c <= x;
	end
	else if(!bState)
	begin
		b <= c;
		c <= x;
		bState <= True;
	end
	else if(!aState)
	begin
		a <=b;
		b <= c;
		c <= x;
		aState <= True;
	end

   endmethod
   method Action deq() if (aState||bState||cState);
        if(aState)
	begin
		aState <= False;
	end
	else if(bState)
	begin
		bState <= False;
	end
	else
	begin
		cState <= False;
	end
   endmethod
   method t first() if (aState||bState||cState);
        if (aState)
	begin
		return a;
	end
	else if (bState)
	begin
		return b;
	end
	else
	begin
		return c;
	end
	
   endmethod
endmodule


// Two elements conflict-free fifo given as black box
module mkCFFifo( Fifo#(2, t) ) provisos (Bits#(t, tSz));
    Ehr#(2, t) da <- mkEhr(?);
    Ehr#(2, Bool) va <- mkEhr(False);
    Ehr#(2, t) db <- mkEhr(?);
    Ehr#(2, Bool) vb <- mkEhr(False);

    rule canonicalize;
        if( vb[1] && !va[1] ) begin
            da[1] <= db[1];
            va[1] <= True;
            vb[1] <= False;
        end
    endrule

    method Action enq(t x) if(!vb[0]);
        db[0] <= x;
        vb[0] <= True;
    endmethod

    method Action deq() if(va[0]);
        va[0] <= False;
    endmethod

    method t first if (va[0]);
        return da[0];
    endmethod
endmodule

module mkCF3Fifo(Fifo#(3,t)) provisos (Bits#(t, tSz));
    FIFO#(t) bsfif <-  mkSizedFIFO(3);
    method Action enq( t x);
        bsfif.enq(x);
    endmethod

    method Action deq();
        bsfif.deq();
    endmethod

    method t first();
        return bsfif.first();
    endmethod

endmodule
