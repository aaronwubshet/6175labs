import TestBenchTemplates::*;
import Multipliers::*;

// Example testbenches
(* synthesize *)
module mkTbDumb();
    function Bit#(16) test_function( Bit#(8) a, Bit#(8) b ) = multiply_unsigned( a, b );
    Empty tb <- mkTbMulFunction(test_function, multiply_unsigned, True);
    return tb;
endmodule

(* synthesize *)
module mkTbFoldedMultiplier();
    Multiplier#(8) dut <- mkFoldedMultiplier();
    Empty tb <- mkTbMulModule(dut, multiply_signed, True);
    return tb;
endmodule

(* synthesize *)
module mkTbSignedVsUnsigned();
    function Bit#(16) test_function1( Bit#(8) a, Bit#(8) b ) = multiply_unsigned( a, b);
    function Bit#(16) test_function2( Bit#(8) a, Bit#(8) b ) = multiply_signed( a, b);
    Empty tb <- mkTbMulFunction(test_function1, test_function2, False);
    return tb;

// TODO: Implement test bench for Exercise 1
endmodule

(* synthesize *)
module mkTbEx3();
	function Bit#(16) test_function11( Bit#(8) a, Bit#(8) b) = multiply_by_adding(a,b);
	function Bit#(16) test_function22( Bit#(8) a, Bit#(8) b) = multiply_unsigned(a,b);
	Empty tb <- mkTbMulFunction(test_function11, test_function22, False);
	return tb;
    // TODO: Implement test bench for Exercise 3
endmodule

(* synthesize *)
module mkTbEx5();
	Multiplier#(8) dut <- mkFoldedMultiplier();
	Empty tb <- mkTbMulModule(dut, multiply_by_adding, True);
	return tb;
 // TODO: Implement test bench for Exercise 5
endmodule

(* synthesize *)
module mkTbEx7a();
	Multiplier#(8) dut <- mkBoothMultiplier();
	Empty tb <- mkTbMulModule(dut, multiply_signed, False);
	return tb;
    // TODO: Implement test bench for Exercise 7
endmodule

(* synthesize *)
module mkTbEx7b();
	Multiplier#(16) dut <- mkBoothMultiplier();
	Empty aa <- mkTbMulModule(dut, multiply_signed, False);
	return aa;
    // TODO: Implement test bench for Exercise 7
endmodule

(* synthesize *)
module mkTbEx9a();
   	Multiplier#(8) dut <- mkBoothMultiplierRadix4();
	Empty tb <- mkTbMulModule(dut, multiply_signed, False);
	return tb;
endmodule

(* synthesize *)
module mkTbEx9b();
   	Multiplier#(16) dut <- mkBoothMultiplierRadix4();
	Empty tb <- mkTbMulModule(dut, multiply_signed, False);
	return tb;
endmodule

