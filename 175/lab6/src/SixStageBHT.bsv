// Six stage with BHT

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
import Bht::*;

// Data structure for different stages

typedef struct {
//	Data inst;
	Addr pc;
	Addr predPc;
	Bool eepoch;
	Bool depoch;
} InstructionFetch2Decode deriving(Bits,Eq);


typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
	Bool eepoch;
	Bool poison;
	Bit#(2) predDir;
} Decode2RegisterFetch deriving (Bits, Eq);

typedef struct {
	Addr pc;
	DecodedInst dInst;
	Addr predPc;
	Data rVal1;
	Data rVal2;
	Data csrVal;
	Bool eepoch;
	Bool poison;
	Bit#(2) predDir;
} RegisterFetch2Execute deriving(Bits, Eq);

typedef struct {
	ExecInst eInst;
	Addr pc;
	Bool eepoch;
	Bool poison;
} Execute2Memory deriving(Bits, Eq);

typedef struct {
	ExecInst eInst;
	Bool eepoch;
	Bool poison;
} Memory2WriteBack deriving(Bits, Eq);


(* synthesize *)
module mkProc(Proc);
    Ehr#(3, Addr)    pcReg <- mkEhr(?);
    RFile            rf <- mkRFile;
	Scoreboard#(6)   sb <- mkCFScoreboard;
	FPGAMemory		iMem <- mkFPGAMemory;
	FPGAMemory		dMem <- mkFPGAMemory;
    CsrFile        csrf <- mkCsrFile;
    Btb#(6)         btb <- mkBtb; // 64-entry BTB
	DirectionPred#(8)	bht <- mkBHT; // 256 entry BHT	
		
	// global epoch for redirection from Execute stage
	Ehr#(2, Bool) exeEpoch <- mkEhr(False);

	// global epoch for reidrction from Decode stage
	Ehr#(2, Bool) decEpoch <- mkEhr(False);
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
			eepoch: exeEpoch[0],
			predPc: predPc,
			depoch: decEpoch[0]		
		};
		pcReg[0]<= predPc;
		f2dFifo.enq(f2d);
		$display("IF is happening PC", f2d.pc);
	endrule
	rule doDecode(csrf.started);
		$display("decoding is starting at pc:", f2dFifo.first.pc);
		let inst <- iMem.resp();
		$display("memory responds with insturction at pc:", f2dFifo.first.pc);
		//decode
		DecodedInst dInst =	decode(inst);
		Decode2RegisterFetch d2r = Decode2RegisterFetch {
			dInst: dInst,
			eepoch: f2dFifo.first.eepoch,
			pc: f2dFifo.first.pc,
			predPc: f2dFifo.first.predPc,
			predDir: bht.getDir(f2dFifo.first.pc)
		};			
		$display("decode is happening pc:", d2r.pc);
	    if(f2dFifo.first.eepoch == exeEpoch[1])
		begin
			$display("execute epochs match at decode pc:", d2r.pc);
			if(f2dFifo.first.depoch == decEpoch[1])
			begin
				if(dInst.iType == Br)
				begin
					$display("decoded instruction is type branch, pc:", d2r.pc);
					let x = fromMaybe(?, dInst.imm) + d2r.pc;
					if(bht.ppcDP(f2dFifo.first.pc, x) != f2dFifo.first.predPc)
					begin
						$display("bht prediction differs from predPc at pc:", d2r.pc);
						pcReg[1] <= bht.ppcDP(f2dFifo.first.pc,x);
						decEpoch[1] <= !decEpoch[1];
						d2r.predPc = bht.ppcDP(f2dFifo.first.pc, x);
					end
				end
				if(dInst.iType == J)
				begin
					let y = fromMaybe(?, dInst.imm) + d2r.pc;
					pcReg[1] <= bht.ppcDP(f2dFifo.first.pc, y);
					decEpoch[1] <= !decEpoch[1];
					d2r.predPc = bht.ppcDP(f2dFifo.first.pc, y);
				end
				d2rFifo.enq(d2r);
				f2dFifo.deq;
			end
			else
			begin	
				f2dFifo.deq;
			end
		end
		else
		begin
			f2dFifo.deq;
		end		
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
			eepoch: d2rFifo.first.eepoch,
			poison: False,
			predDir: d2rFifo.first.predDir
		};
		$display("register fetch at pc:", r2e.pc);
		if (d2rFifo.first.eepoch == exeEpoch[1])
		begin
			$display("execute epochs match at pc:", r2e.pc);
			$display("instruction is not poisoned. pc is:",r2e.pc);
			let stall = sb.search1(dInst.src1) || sb.search2(dInst.src2);
			if (!stall) 
			begin	
				$display("instruction is not stalled at pc:", r2e.pc);
				sb.insert(dInst.dst);
				r2eFifo.enq(r2e);
				d2rFifo.deq;
			end
			else
			begin
				$display("stalled at pc:", r2e.pc);
			end
		end
		else
		begin
			sb.insert(dInst.dst);
			r2e.poison = True;
			$display("execute epochs don't match at pc:", r2e.pc);
			r2eFifo.enq(r2e);
			d2rFifo.deq;
		end
	endrule

	rule doExecute(csrf.started);
		let r2e = r2eFifo.first;
		ExecInst eInst = exec(r2e.dInst, r2e.rVal1,r2e.rVal2, r2e.pc, r2e.predPc, r2e.csrVal);
		Execute2Memory e2m = Execute2Memory {
			eInst: eInst,
			eepoch: r2eFifo.first.eepoch,
			pc: r2eFifo.first.pc,
			poison: r2eFifo.first.poison
		};
		if(e2m.poison)
		begin
			e2mFifo.enq(e2m);	
			r2eFifo.deq;
		end
		else
		begin
			$display("execute stage is firing at pc:", e2m.pc);
			if(r2e.eepoch == exeEpoch[1])
			begin
				$display("execute epochs match at pc:", e2m.pc);
				if(eInst.iType == Br)
				begin
					$display("instruction is not poisoned and a branch at pc:", e2m.pc);
					bht.update(e2m.pc, eInst.brTaken);
				end
			    if (eInst.mispredict)
				begin
					$display("valid instruction mispredict", e2m.pc);
					pcReg[2] <= eInst.addr;
					if (r2e.predDir == 2'b11|| r2e.predDir == 2'b00)
					begin 
						$display("btb is being updated at pc:", e2m.pc);
						btb.update(r2e.pc, eInst.addr);			
					end
					exeEpoch[1] <= !exeEpoch[1];
				end
				else if (eInst.iType == J)
				begin
					$display("instruction is a jump and not poisoned at pc:", e2m.pc);
//					if(r2e.predDir == 2'b11 || r2e.predDir == 2'b00)
//					begin	
						$display("btb is being updated during jump at pc:", e2m.pc);
						btb.update(r2e.pc, eInst.addr);
//					end
				end
				$display("instruction is not poisoned at pc:", e2m.pc);
				r2eFifo.deq;
				e2mFifo.enq(e2m);
			end
			else
			begin
				e2m.poison = True;
				e2mFifo.enq(e2m);
				r2eFifo.deq;
			end
		end
	endrule

	rule doMemory(csrf.started);
		let e2m = e2mFifo.first;
		$display("entering mem at pc:", e2m.pc);
		Memory2WriteBack m2w = Memory2WriteBack {
			eInst: e2m.eInst,
			poison: e2m.poison,
			eepoch: e2m.eepoch
		};

		if (e2m.poison)
		begin
			$display("insturction is poisioned at pc:", e2m.pc);
			m2wFifo.enq(m2w);
		end
		else
		begin
			$display("instruction is fine at pc:", e2m.pc);
			if(e2m.eInst.iType == Ld)
			begin
				$display("instruction is a load; request at pc:", e2m.pc);
				dMem.req(MemReq{op: Ld, addr: e2m.eInst.addr, data:?});
			end
			else if(e2m.eInst.iType == St)
			begin
				$display("instrution is a store at pc:", e2m.pc);
				dMem.req(MemReq{op: St, addr: e2m.eInst.addr, data: e2m.eInst.data});
			end
			m2wFifo.enq(m2w);
		end
		e2mFifo.deq;
		$display("exitting mem stage at pc:", e2m.pc);
		
	endrule

	rule doWriteBack(csrf.started);
		$display("entering writeback");
		let m2w = m2wFifo.first;
		if(!m2w.poison)
		begin
			$display("write back stage and not poison at pc", pcReg[0]);
			if(m2w.eInst.iType == Ld)
			begin
				$display("above instruction is a load");
				m2w.eInst.data <-dMem.resp();
			end
			if (isValid(m2w.eInst.dst)) 
			begin	
				$display("above instruction has a valid desitation");
				rf.wr(fromMaybe(?, m2w.eInst.dst), m2w.eInst.data);
			end
			csrf.wr(m2w.eInst.iType == Csrw ? m2w.eInst.csr : Invalid, m2w.eInst.data);
		end
		sb.remove;
		m2wFifo.deq;
		$display("writeback is exiting");
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

