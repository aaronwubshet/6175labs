import Multiplexer::*;

// Full adder functions

function Bit#(1) fa_sum( Bit#(1) a, Bit#(1) b, Bit#(1) c_in );
    return xor1( xor1( a, b ), c_in );
endfunction

function Bit#(1) fa_carry( Bit#(1) a, Bit#(1) b, Bit#(1) c_in );
    return or1( and1( a, b ), and1( xor1( a, b ), c_in ) );
endfunction

// 4 Bit full adder

function Bit#(5) add4( Bit#(4) a, Bit#(4) b, Bit#(1) c_in );
	Bit#(4) out = 0;
	for (Integer i=0; i<4; i=i+1)
	begin
		out[i] = fa_sum(a[i], b[i], c_in);
		c_in = fa_carry(a[i], b[i], c_in);
	end
	return {c_in , out};
endfunction

// Adder interface

interface Adder8;
    method ActionValue#( Bit#(9) ) sum( Bit#(8) a, Bit#(8) b, Bit#(1) c_in );
endinterface

// Adder modules

// RC = Ripple Carry
module mkRCAdder( Adder8 );
    method ActionValue#( Bit#(9) ) sum( Bit#(8) a, Bit#(8) b, Bit#(1) c_in );
        Bit#(5) lower_result = add4( a[3:0], b[3:0], c_in );
        Bit#(5) upper_result = add4( a[7:4], b[7:4], lower_result[4] );
        return { upper_result , lower_result[3:0] };
    endmethod
endmodule

// CS = Carry Select
module mkCSAdder( Adder8 );
    method ActionValue#( Bit#(9) ) sum( Bit#(8) a, Bit#(8) b, Bit#(1) c_in );
	Bit#(8) s = 0;
	Bit#(1) c_out = 0;
	Bit#(5) r2 = add4( a[7:4], b[7:4], 1);
	Bit#(5) r1 = add4( a[7:4], b[7:4], 0);
	Bit#(5) r3 = add4( a[3:0], b[3:0], c_in);
	c_out = multiplexer1(r3[4],r1[4], r2[4]);
	s[3:0] = r3[3:0];
	s[7:4] = multiplexer_n(r3[4], r1[3:0], r2[3:0]);
	return {c_out, s};
    endmethod
endmodule

