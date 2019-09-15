// Six stage

import Types::*;
import ProcTypes::*;
import MemTypes::*;
import MemInit::*;
import RFile::*;
import Decode::*;
import Exec::*;
import DMemory::*;
import IMemory::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import Scoreboard::*;
import FPGAMemory::*;


// Data structure for different stages

typedef struct {
//	Data inst;
	Addr pc;
	Addr predPc;
	Bool epoch;
} InstructionFetch2Decode deriving(Bits,Eq);


typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
	Bool epoch;
} Decode2RegisterFetch deriving (Bits, Eq);

typedef struct {
	Addr pc;
	DecodedInst dInst;
	Addr predPc;
	Data rVal1;
	Data rVal2;
	Data csrVal;
	Bool epoch;
} RegisterFetch2Execute deriving(Bits, Eq);

typedef struct {
	ExecInst eInst;
	Addr pc;
	Bool epoch;
	Bool poison;
} Execute2Memory deriving(Bits, Eq);

typedef struct {
	ExecInst eInst;
	Bool epoch;
	Bool poison;
} Memory2WriteBack deriving(Bits, Eq);


(* synthesize *)
module mkProc(Proc);
    Ehr#(2, Addr)    pcReg <- mkEhr(?);
    RFile            rf <- mkRFile;
	Scoreboard#(6)   sb <- mkCFScoreboard;
	FPGAMemory		iMem <- mkFPGAMemory;
	FPGAMemory		dMem <- mkFPGAMemory;
    CsrFile        csrf <- mkCsrFile;
    Btb#(6)         btb <- mkBtb; // 64-entry BTB
	
		
	// global epoch for redirection from Execute stage
	Ehr#(2, Bool) exeEpoch <- mkEhr(False);

	// FIFO between stages
	Fifo#(2, InstructionFetch2Decode) f2dFifo <- mkCFFifo;

	Fifo#(2, Decode2RegisterFetch) d2rFifo <- mkCFFifo;

	Fifo#(2, RegisterFetch2Execute) r2eFifo <- mkCFFifo;

	Fifo#(2, Execute2Memory) e2mFifo <- mkCFFifo;

	Fifo#(2, Memory2WriteBack) m2wFifo <- mkCFFifo;

	Bool memReady = dMem.init.done() && iMem.init.done();
		

	rule doInstructionFetch(csrf.started);
		// fetch
		iMem.req(MemReq{op: Ld, addr: pcReg[0], data:?});
		Addr predPc = btb.predPc(pcReg[0]);
		InstructionFetch2Decode f2d =InstructionFetch2Decode {	
			pc: pcReg[0],
			epoch: exeEpoch[0],
			predPc: predPc
		};
		pcReg[0]<= predPc;
		f2dFifo.enq(f2d);
		$display("IF is firing");
	endrule
	rule doDecode(csrf.started);
		let inst <- iMem.resp();
		//decode
		DecodedInst dInst =	decode(inst);
		Decode2RegisterFetch d2r = Decode2RegisterFetch {
			dInst: dInst,
			epoch: f2dFifo.first.epoch,
			pc: f2dFifo.first.pc,
			predPc: f2dFifo.first.predPc
		};			
		d2rFifo.enq(d2r);
		f2dFifo.deq;
		$display("decode is firing");
	endrule

	rule doRegisterFetch(csrf.started);	
		// reg read		
		let dInst = d2rFifo.first.dInst;
		Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
		Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
		Data csrVal = csrf.rd(fromMaybe(?,dInst.csr));
		RegisterFetch2Execute r2e = RegisterFetch2Execute {
			pc: d2rFifo.first.pc,
			predPc: d2rFifo.first.predPc,
			dInst: d2rFifo.first.dInst,
			rVal1: rVal1,
			rVal2: rVal2,
			csrVal: csrVal,
			epoch: d2rFifo.first.epoch
		};		
		let stall = sb.search1(dInst.src1) || sb.search2(dInst.src2);
		if (!stall) 
		begin	
			sb.insert(dInst.dst);
			r2eFifo.enq(r2e);
			d2rFifo.deq;
		end
		else
		begin
			$display("stalled");
		end
		$display("reg fetch is firing");
	endrule

	rule doExecute(csrf.started);
		let r2e = r2eFifo.first;
		ExecInst eInst = exec(r2e.dInst, r2e.rVal1,r2e.rVal2, r2e.pc, r2e.predPc, r2e.csrVal);
		Execute2Memory e2m = Execute2Memory {
			eInst: eInst,
			epoch: r2eFifo.first.epoch,
			pc: r2eFifo.first.pc,
			poison: False
		};
		
	
		if(r2e.epoch != exeEpoch[1])
		begin
			e2m.poison = True;
		end
		else
		begin
			if (eInst.mispredict)
			begin
				pcReg[1] <= eInst.addr;
				btb.update(r2e.pc, eInst.addr);			
				exeEpoch[1] <= !exeEpoch[1];
			end
			e2m.poison = False;
		end
		
		r2eFifo.deq;		
		e2mFifo.enq(e2m);
		$display("exectue is firing");
	endrule

	rule doMemory(csrf.started);
		let e2m = e2mFifo.first;
		Memory2WriteBack m2w = Memory2WriteBack {
			eInst: e2m.eInst,
			poison: e2m.poison,
			epoch: e2m.epoch
		};
		if (e2m.poison)
		begin
			m2wFifo.enq(m2w);
		end
		else
		begin
			if(e2m.eInst.iType == Ld)
			begin
				dMem.req(MemReq{op: Ld, addr: e2m.eInst.addr, data:?});
			end
			else if(e2m.eInst.iType == St)
			begin
				dMem.req(MemReq{op: St, addr: e2m.eInst.addr, data: e2m.eInst.data});
			end
			m2wFifo.enq(m2w);
		end
		e2mFifo.deq;
		
		$display("mem is firing");
	endrule

	rule doWriteBack(csrf.started);
		let m2w = m2wFifo.first;
		if(!m2w.poison)
		begin
			if(m2w.eInst.iType == Ld)
			begin
				m2w.eInst.data <-dMem.resp();
			end
			if (isValid(m2w.eInst.dst)) 
			begin	
				rf.wr(fromMaybe(?, m2w.eInst.dst), m2w.eInst.data);
			end
			csrf.wr(m2w.eInst.iType == Csrw ? m2w.eInst.csr : Invalid, m2w.eInst.data);
		end
		sb.remove;
		m2wFifo.deq;
		$display("wb is firing");
	endrule
		
	

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
	$display("Start cpu");
        csrf.start(0); // only 1 core, id = 0
        pcReg[0] <= startpc;
    endmethod

	interface dMemInit = dMem.init;
	interface iMemInit = iMem.init;
		
endmodule

