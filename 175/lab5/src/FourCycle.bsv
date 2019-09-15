// FourCycle.bsv
//
// This is a four cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DelayedMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
typedef enum {
	Fetch,
	Decode,
	Execute,
	WriteBack
} Stage deriving(Bits, Eq, FShow);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr)    pc <- mkRegU;
    RFile         rf <- mkRFile;
    DelayedMemory mem <- mkDelayedMemory;
	let dummyInit     <- mkDummyMemInit;
    CsrFile       csrf <- mkCsrFile;
	Reg#(Stage) state <- mkReg(Fetch);
	Reg#(Data) f2d <- mkRegU;
	Reg#(DecodedInst) d2e <- mkRegU;
	Reg#(ExecInst) e2w <- mkRegU;
    Bool memReady = mem.init.done && dummyInit.done;

	rule test (!memReady);
		let e = tagged InitDone;
		mem.init.request.put(e);
		dummyInit.request.put(e);
	endrule

	rule doFetch(csrf.started && state == Fetch);
		//get instruction at pc
		mem.req(MemReq{op: Ld, addr: pc, data:?});
		
		state <= Decode;
	endrule

	rule doDecode(csrf.started && state == Decode);
		let inst <- mem.resp();
		
		DecodedInst dInst = decode(inst);
		d2e <= dInst;
		Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
		Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
		Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));		
		state <= Execute;
	endrule

	rule doExecute(csrf.started && state == Execute);
		let dInst = d2e;
		
		Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
		Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
		Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));		
		ExecInst eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);
		if (eInst.iType == St)
		begin
			mem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
		end 
		if (eInst.iType == Ld)
		begin
			mem.req(MemReq{op: Ld, addr: eInst.addr, data:?});
		end
		pc <= eInst.brTaken ? eInst.addr : pc + 4;
		e2w <= eInst;
		state <= WriteBack;
	endrule

	rule doWriteBack(csrf.started && state == WriteBack);
		let eInst = e2w;
		if (eInst.iType == Ld)
		begin
			eInst.data <- mem.resp();
		end
		if (isValid(eInst.dst))
		begin
			rf.wr(fromMaybe(?, eInst.dst), eInst.data);
		end
		csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
		state <= Fetch;
	endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc <= startpc;
    endmethod

	interface iMemInit = dummyInit;
    interface dMemInit = mem.init;
endmodule

