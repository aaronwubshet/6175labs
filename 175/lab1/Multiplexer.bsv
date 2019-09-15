function Bit#(1) and1(Bit#(1) a, Bit#(1) b);
    return a & b;
endfunction

function Bit#(1) or1(Bit#(1) a, Bit#(1) b);
    return a | b;
endfunction

function Bit#(1) xor1( Bit#(1) a, Bit#(1) b );
    return a ^ b;
endfunction

function Bit#(1) not1(Bit#(1) a);
    return ~ a;
endfunction

function Bit#(1) multiplexer1(Bit#(1) sel, Bit#(1) a, Bit#(1) b);
// That's a very hard and expansive way to write a multiplexer.
// As you said in your discussion file that you know this way is more complicated than the 4 gates one,
// that's ok. But keep in mind that the way you write the circuit actually matters a lot.
// It is extremely rare (I would say never) in this class to implement
// a boolean function by building its truth table and using de morgan's law.
// Remark: the schema of a multiplexer was given in class :).
    Bit#(1) nota = not1(a);
    Bit#(1) notb = not1(b);
    Bit#(1) nots = not1(sel);
    Bit#(1) g1 = or1(nota, b);
    g1 = or1(g1, sel);
    Bit#(1) g2 = or1(nota, notb);
    g2 = or1(g2, sel);
    Bit#(1) g3 = or1(a, notb);
    g3 = or1(g3, nots);
    Bit#(1) g4 = or1(nota, notb);
    g4 = or1(g4, nots);
    return not1(and1(and1(and1(g1, g2),g3),g4));
endfunction

function Bit#(5) multiplexer5(Bit#(1) sel, Bit#(5) a, Bit#(5) b);
	return multiplexer_n(sel, a, b);   
 //Bit#(5) out = 0;
    //for (Integer i = 0; i<5; i = i+1)
    //begin
      //   out[i] = multiplexer1(sel, a[i], b[i]);
    //end
    //return out; 
endfunction

typedef 5 N;
function Bit#(N) multiplexerN(Bit#(1) sel, Bit#(N) a, Bit#(N) b);
    Bit#(N) out = 0;
    for (Integer i = 0; i<valueOf(N); i = i+1)
    begin
	  out[i] = multiplexer1(sel, a[i], b[i]);
    end
    return out;
endfunction

//typedef 32 N; // Not needed
function Bit#(n) multiplexer_n(Bit#(1) sel, Bit#(n) a, Bit#(n) b);
    Bit#((n)) out = 0;
    for (Integer i = 0; i<valueOf(n); i = i+1)
    begin 
	  out[i] = multiplexer1(sel, a[i], b[i]);
    end
    return out;
endfunction

