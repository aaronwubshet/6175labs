import Vector::*;
import Complex::*;

import FftCommon::*;
import Fifo::*;
import FIFOF::*;

interface Fft;
    method Action enq(Vector#(FftPoints, ComplexData) in);
    method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
endinterface


(* synthesize *)
module mkFftCombinational(Fft);
    FIFOF#(Vector#(FftPoints, ComplexData)) inFifo <- mkFIFOF;
    FIFOF#(Vector#(FftPoints, ComplexData)) outFifo <- mkFIFOF;
    Vector#(NumStages, Vector#(BflysPerStage, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));

    function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in);
        Vector#(FftPoints, ComplexData) stage_temp, stage_out;
        for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)  begin
            FftIdx idx = i * 4;
            Vector#(4, ComplexData) x;
            Vector#(4, ComplexData) twid;
            for (FftIdx j = 0; j < 4; j = j + 1 ) begin
                x[j] = stage_in[idx+j];
                twid[j] = getTwiddle(stage, idx+j);
            end
            let y = bfly[stage][i].bfly4(twid, x);

            for(FftIdx j = 0; j < 4; j = j + 1 ) begin
                stage_temp[idx+j] = y[j];
            end
        end

        stage_out = permute(stage_temp);

        return stage_out;
    endfunction
  
    rule doFft;
            inFifo.deq;
            Vector#(4, Vector#(FftPoints, ComplexData)) stage_data;
            stage_data[0] = inFifo.first;
      
            for (StageIdx stage = 0; stage < 3; stage = stage + 1) begin
                stage_data[stage+1] = stage_f(stage, stage_data[stage]);
            end
            outFifo.enq(stage_data[3]);
    endrule
    
    method Action enq(Vector#(FftPoints, ComplexData) in);
        inFifo.enq(in);
    endmethod
  
    method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod
endmodule

(* synthesize *)
module mkFftInelasticPipeline(Fft);
    FIFOF#(Vector#(FftPoints, ComplexData)) inFifo <- mkFIFOF;
    FIFOF#(Vector#(FftPoints, ComplexData)) outFifo <- mkFIFOF;
    Vector#(3, Vector#(16, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));
    
    Reg#(Vector#(64, ComplexData)) a <- mkRegU();
    Reg#(Bool) va <- mkReg(False); 
    Reg#(Vector#(64, ComplexData)) b <- mkRegU();
    Reg#(Bool) vb <- mkReg(False);
	function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in);
        	Vector#(FftPoints, ComplexData) stage_temp, stage_out;
	        for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)  begin
        	    FftIdx idx = i * 4;
	            Vector#(4, ComplexData) x;
        	    Vector#(4, ComplexData) twid;
	            for (FftIdx j = 0; j < 4; j = j + 1 ) begin
        	        x[j] = stage_in[idx+j];
                	twid[j] = getTwiddle(stage, idx+j);
	            end
        	    let y = bfly[stage][i].bfly4(twid, x);

		for(FftIdx j = 0; j < 4; j = j + 1 ) begin
                	stage_temp[idx+j] = y[j];
	        end
       		end
	        stage_out = permute(stage_temp);
        	return stage_out;
	endfunction
  
    rule doFft;
	
	if(outFifo.notFull || !va)
	begin
		if(inFifo.notEmpty)
		begin
			b <= stage_f(0,(inFifo.first));
			inFifo.deq;
			vb <= True;
		end
		else
		begin
			vb <= False;
		end
			a <= stage_f(1,(b));
			va <= vb;
		
		if (va)
		begin
			outFifo.enq(stage_f(2,a));
		end
	end
     
    endrule

    method Action enq(Vector#(FftPoints, ComplexData) in);
        inFifo.enq(in);
    endmethod
  
    method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod
endmodule

(* synthesize *)
module mkFftElasticPipeline(Fft);
    FIFOF#(Vector#(FftPoints, ComplexData)) inFifo <- mkFIFOF;
    FIFOF#(Vector#(FftPoints, ComplexData)) outFifo <- mkFIFOF;
    Vector#(3, Vector#(16, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));
    Fifo#(2, Vector#(64, ComplexData)) b <- mkCFFifo;
    Fifo#(2, Vector#(64, ComplexData)) a <- mkCFFifo;	
	    
//TODO: Implement the rest of this module
    // You should use more than one rule
    	function Vector#(FftPoints, ComplexData) stage_f(StageIdx stage, Vector#(FftPoints, ComplexData) stage_in);
        	Vector#(FftPoints, ComplexData) stage_temp, stage_out;
	        for (FftIdx i = 0; i < fromInteger(valueOf(BflysPerStage)); i = i + 1)  begin
        	    FftIdx idx = i * 4;
	            Vector#(4, ComplexData) x;
        	    Vector#(4, ComplexData) twid;
	            for (FftIdx j = 0; j < 4; j = j + 1 ) begin
        	        x[j] = stage_in[idx+j];
                	twid[j] = getTwiddle(stage, idx+j);
	            end
        	    let y = bfly[stage][i].bfly4(twid, x);

		for(FftIdx j = 0; j < 4; j = j + 1 ) begin
                	stage_temp[idx+j] = y[j];
	        end
       		end
	        stage_out = permute(stage_temp);
        	return stage_out;
	endfunction
  

    rule stage1;
	b.enq(stage_f(0,inFifo.first));
	inFifo.deq;
    endrule
    rule stage2;
	a.enq(stage_f(1,b.first));
	b.deq;
    endrule
    rule stage3;
	outFifo.enq(stage_f(2, a.first));
	a.deq;
    endrule

    method Action enq(Vector#(FftPoints, ComplexData) in);
        inFifo.enq(in);
    endmethod
  
    method ActionValue#(Vector#(FftPoints, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod
endmodule

