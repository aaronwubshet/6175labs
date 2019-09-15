// Reference functions that use Bluespec's '*' operator
function Bit#(TAdd#(n,n)) multiply_unsigned( Bit#(n) a, Bit#(n) b );
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack( product_uint );
endfunction

function Bit#(TAdd#(n,n)) multiply_signed( Bit#(n) a, Bit#(n) b );
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack( product_int );
endfunction



// Multiplication by repeated addition
function Bit#(TAdd#(n,n)) multiply_by_adding( Bit#(n) a, Bit#(n) b );
    // TODO: Implement this function in Exercise 2
	Bit#(n) tp = 0;
	Bit#(n) prod = 0;
	for (Integer i=0; i<valueOf(n); i=i+1)
	begin
		Bit#(n) m = (a[i]==0)? 0 : b;
		Bit#(TAdd#(n,1)) sum = zeroExtend(m) + zeroExtend(tp);
		prod[i] = sum[0];
		tp = sum[valueOf(n):1];
	end
    return {tp,prod};
	
endfunction



// Multiplier Interface
interface Multiplier#( numeric type n );
    method Bool start_ready();
    method Action start( Bit#(n) a, Bit#(n) b );
    method Bool result_ready();
    method ActionValue#(Bit#(TAdd#(n,n))) result();
endinterface



// Folded multiplier by repeated addition
module mkFoldedMultiplier( Multiplier#(n) )
	provisos(Add#(1, a__, n)); // make sure n >= 1
    
    // You can use these registers or create your own if you want
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(n)) prod <- mkRegU();
    Reg#(Bit#(n)) tp <- mkReg(0);	
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );
//    Reg#(Bool) busy <- mkReg(False);
    rule mulStep if (i<fromInteger(valueOf(n)));
	Bit#(n) m = (a[0] == 0)? 0: b;
	a <= a >>1;
	Bit#(TAdd#(n,1)) sum = zeroExtend(m) + zeroExtend(tp);
	prod <= {sum[0], prod[(valueOf(n)-1):1]};
	tp <= sum[valueOf(n):1];
	i <= i + 1;
    endrule

    method Bool start_ready();
	if (i==fromInteger(valueOf(n) +1)) begin 
		
		return True; end
	else begin return False; end
//	if (busy)
//		return False;
//	else
//		return True;
    endmethod
 
    method Action start( Bit#(n) aIn, Bit#(n) bIn ); // if(!busy) ;
        a<= aIn;
	b<=bIn;
	tp <=0;
//	busy <= True;
	i<=0;
    endmethod

    method Bool result_ready();
        if (i == fromInteger(valueOf(n)))// && busy)
	begin
		return True;
	end
	else begin
		return False;
	end
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result() ;
//        busy <= False;
	i<=fromInteger(valueOf(n)+1);
	return {tp,prod};

    endmethod
endmodule



// Booth Multiplier
module mkBoothMultiplier( Multiplier#(n) )
	provisos(Add#(2, a__, n)); // make sure n >= 2

    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n))+1 );
    
//    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) temp1 <- mkRegU;
  //  Reg#(Bit#(TAdd#(TAdd#(n,n),1))) temp2 <- mkRegU;
    rule mul_step if (i<fromInteger(valueOf(n)));
	let pr = p[1:0];
	let temp1= (p+m_pos);
	let temp2= (p+m_neg);
	case (pr)
	2'b01: p <={temp1[valueOf(n)*2],(temp1[(valueOf(n)*2):1])};
	2'b10: p <={temp2[valueOf(n)*2],(temp2[(valueOf(n)*2):1])};
	default: p<={p[valueOf(n)*2], p[(valueOf(n)*2):1]};
	endcase
	
	i <= i +1;



    endrule

    method Bool start_ready();
       	if (i==fromInteger(valueOf(n))+1) begin 
		return True; end
	else begin return False; end
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r );
        m_pos<= {m,0};
	m_neg <={-m, 0};
	p <= {0, r, 1'b0};
	i<=0;
    endmethod

    method Bool result_ready();
         if (i == fromInteger(valueOf(n)))
	begin
		return True;
	end
	else begin
		return False;
	end
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();

	i <= fromInteger(valueOf(n)+1);
	return p[valueOf(n)*2:1];
    endmethod
endmodule



// Radix-4 Booth Multiplier
module mkBoothMultiplierRadix4( Multiplier#(n) )
	provisos(Mul#(a__, 2, n), Add#(1, b__, a__)); // make sure n >= 2 and n is even

    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)/2+1) );

    rule mul_step  if (i < fromInteger(valueOf(n)/2));
	let pr = p[2:0];
	let temp1 = p+m_pos;
	let temp2 = p+m_neg;
	let temp3 = m_pos << 1;
	let temp4 = p+temp3;//use this one
	let temp5 = m_neg <<1;
	let temp6 = p+temp5; // use this one too
	case (pr)
	3'b000: p <= {p[1+(valueOf(n)*2)],p[1+(valueOf(n)*2)], p[1+(valueOf(n)*2):2]};
	3'b001: p<= {temp1[1+(valueOf(n)*2)],temp1[1+(valueOf(n)*2)], temp1[1+(valueOf(n)*2):2]};
	3'b010: p<= {temp1[1+(valueOf(n)*2)],temp1[1+(valueOf(n)*2)], temp1[1+(valueOf(n)*2):2]};
	3'b011:  p<= {temp4[1+(valueOf(n)*2)],temp4[1+(valueOf(n)*2)], temp4[1+(valueOf(n)*2):2]};
	3'b100: p<= {temp6[1+(valueOf(n)*2)],temp6[1+(valueOf(n)*2)], temp6[1+(valueOf(n)*2):2]};
	3'b101: p<= {temp2[1+(valueOf(n)*2)],temp2[1+(valueOf(n)*2)], temp2[1+(valueOf(n)*2):2]};
	3'b110: p<= {temp2[1+(valueOf(n)*2)],temp2[1+(valueOf(n)*2)], temp2[1+(valueOf(n)*2):2]};
	3'b111: p <= {p[1+(valueOf(n)*2)],p[1+(valueOf(n)*2)], p[1+(valueOf(n)*2):2]};
	endcase
	i <= i +1;
    endrule

    method Bool start_ready();
        if (i == fromInteger(valueOf(n)/2+1))
		return True;
	else
		return False;
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r );
        m_pos <= {m[valueOf(n)-1], m, 0};
	m_neg <= {(-m)[valueOf(n) -1], -m, 0};
	p <= {0, r, 1'b0};
	i <= 0;
    endmethod

    method Bool result_ready();
        if (i == fromInteger(valueOf(n)/2))
		return True;
	else
		return False;
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result();
	i <= fromInteger(valueOf(n)/2+1);
        return p[2*valueOf(n):1];
    endmethod
endmodule

