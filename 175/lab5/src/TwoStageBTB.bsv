// TwoStageBTB.bsv
//
// This is a two stage pipelined (with BTB) implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import GetPut::*;

typedef struct {
	Data inst;
	Addr pc;
	Addr ppc;
} Dec2Ex deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr) pc <- mkRegU;
    RFile      rf <- mkRFile;
	IMemory  iMem <- mkIMemory;
    DMemory  dMem <- mkDMemory;
    CsrFile  csrf <- mkCsrFile;
    Btb#(6)   btb <- mkBtb; // 64-entry BTB
	 Reg#(Maybe#(Dec2Ex)) ir <- mkReg(tagged Invalid);	
    Bool memReady = iMem.init.done() && dMem.init.done();
	Reg#(Addr) temp_pc <- mkRegU;

	rule test (!memReady);
		let e = tagged InitDone;
		iMem.init.request.put(e);
		dMem.init.request.put(e);
	endrule

	rule doProc(csrf.started);
		let newInst = iMem.req(pc);
		let newppc = btb.predPc(pc);
		let newpc = pc;
		let newIR = Valid(Dec2Ex{inst: newInst, pc: newpc, ppc: newppc});
		
		if (isValid(ir))
		begin
			let x = fromMaybe(?, ir);
			let inst = x.inst;
			let irpc = x.pc;
			let ppc = x.ppc;
			let dInst = decode(inst);
			Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
			Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
			Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));
			ExecInst eInst = exec(dInst, rVal1, rVal2, irpc, ppc, csrVal);
			if (eInst.iType == Ld)
			begin
				eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
			end
			else if (eInst.iType == St)
			begin	
				let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
			end
			if (isValid(eInst.dst))
			begin	
				rf.wr(fromMaybe(?, eInst.dst), eInst.data);
			end
			
			if (eInst.mispredict)
			begin
				btb.update(irpc, eInst.addr);
				newIR = tagged Invalid;
				newppc = eInst.addr;
			end
			csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
			
		end
		pc <= newppc;
		ir <= newIR;
		
	endrule




    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc <= startpc;
    endmethod

	interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule

