// Six-stage with BHT
import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import ICache::*;
import DCache::*;
import MemReqIDGen::*;
import CacheTypes::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MessageFifo::*;
import RefTypes::*;
import Btb::*;
import Bht::*;
import Scoreboard::*;

typedef struct {
	Addr pc;
	Addr predPc;
	Bool eEpoch;
        Bool dEpoch; 
} Fetch2Decode deriving (Bits, Eq);

typedef struct {
	Addr pc;
	Addr predPc;
	Bool eEpoch;
	DecodedInst dInst;
	Data inst;
        Counter brDir;
} Decode2Reg deriving (Bits, Eq);

typedef struct {
	Addr pc;
	Addr predPc;
	Bool eEpoch;
	DecodedInst dInst;
	Data rVal1;
	Data rVal2;
	Data csrVal;
        Counter brDir;
} Reg2Exec deriving (Bits, Eq);

typedef struct {
	Addr pc;
	DecodedInst dInst;
	Bool eEpoch;
	Bool killed;
	ExecInst eInst;
} Exec2Mem deriving (Bits, Eq);

typedef struct {
	Addr pc;
	ExecInst eInst;
	Bool killed;
} Mem2WB deriving (Bits, Eq);

// redirect msg from Execute stage
typedef struct {
	Addr pc;
	Addr nextPc;
        Bool updateBtb;
} ExeRedirect deriving (Bits, Eq);

typedef struct {
	Addr pc;
	Addr nextPc;
} BtbUpdate deriving (Bits, Eq);

typedef struct {
	Addr pc;
	Bool taken;
} BhtUpdate deriving (Bits, Eq);

module mkCore#(CoreID id)(
	WideMem iMem, 
	RefDMem refDMem, // debug: reference data mem
	Core ifc
    );
    Ehr#(3, Addr) 	pcReg 	<- mkEhr(?);
    Scoreboard#(6)	sb 	<- mkPipelineScoreboard;
    CsrFile        	csrf 	<- mkCsrFile(id);
    RFile		rf 	<- mkBypassRFile;
    Btb#(6)        	btb 	<- mkBtb; // 64-entry BTB
    Bht#(8)		bht 	<- mkBht; // 256-entry BHT

    // mem req id
    MemReqIDGen memReqIDGen <- mkMemReqIDGen;

    // I mem
    ICache iCache <- mkICache(iMem);

    // D cache
    MessageFifo#(2) toParentQ <- mkMessageFifo;
    MessageFifo#(2) fromParentQ <- mkMessageFifo;
    DCache dCache <- mkDCache(
        id,
        toMessageGet(fromParentQ),
        toMessagePut(toParentQ),
        refDMem
    );

    // global epochs for redirections from Execute/Decode stages
    Ehr#(2, Bool) eEpoch <- mkEhr(False);
    Ehr#(2, Bool) dEpoch <- mkEhr(False);

    // whether to update the bht/btb
    Ehr#(2, Maybe#(BtbUpdate)) btbUpdate <- mkEhr(Invalid);
    Ehr#(2, Maybe#(BhtUpdate)) bhtUpdate <- mkEhr(Invalid);

    // Whether the pipeline is stalled this cycle
    Ehr#(2, Bool) stall <- mkEhr(False);

    // FIFO between fetch/decode
    Fifo#(1, Fetch2Decode) f2dFifo <- mkPipelineFifo;
    // Fifo between decode/regfetch
    Fifo#(1, Decode2Reg) d2rFifo <- mkPipelineFifo;
    // Fifo between regfetch/execute
    Fifo#(1, Reg2Exec) r2eFifo <- mkPipelineFifo;
    // Fifo between execute/mem
    Fifo#(1, Exec2Mem) e2mFifo <- mkPipelineFifo;
    // Fifo between mem/wb
    Fifo#(1, Mem2WB) m2wFifo <- mkPipelineFifo;

    // fetch stage
    rule doFetch(csrf.started && !stall[1]);
	if(btbUpdate[1] matches tagged Valid .r) begin
	    btb.update(r.pc, r.nextPc);
	end

	if(bhtUpdate[1] matches tagged Valid .r) begin
	    bht.update(r.pc, r.taken);
	end

	btbUpdate[1] <= Invalid;
	bhtUpdate[1] <= Invalid;
	
	// fetch
	iCache.req(pcReg[2]);
	Addr predPc = btb.predPc(pcReg[2]);

	// update pc for next time
	pcReg[2] <= predPc;

	$display("FETCH pc = %x, ppc = %x", pcReg[2], predPc);
	Fetch2Decode f2d = Fetch2Decode {
	    pc: pcReg[2],
	    predPc: predPc,
	    eEpoch: eEpoch[1],
            dEpoch: dEpoch[1]
	};
	f2dFifo.enq(f2d);
    endrule

    rule doDecode(csrf.started && !stall[1]);
	let f2d = f2dFifo.first;
	f2dFifo.deq;
		
	let inst <- iCache.resp;

	$display("DECODE: PC = %x, raw inst = %x", f2d.pc, inst);
	if (eEpoch[1] == f2d.eEpoch && dEpoch[0] == f2d.dEpoch) begin
    	    // decode
	    DecodedInst dInst = decode(inst);

	    // check the branch prediction
	    let ppcDP = (dInst.iType == Br) ? 
		bht.ppcDP(f2d.pc, f2d.pc + fromMaybe(?, dInst.imm)) :
		    (dInst.iType == J) ? f2d.pc + fromMaybe(?, dInst.imm) : f2d.predPc; 
		    
	    // redirect if necessary
            if (ppcDP != f2d.predPc && !isValid(btbUpdate[1])) begin
		dEpoch[0] <= !dEpoch[0];
		pcReg[1] <= ppcDP;
 		$display("Fetch: Mispredict found during decode, pc redirected to %x", ppcDP);
	    end	
	
	    Decode2Reg d2r = Decode2Reg {
		pc: f2d.pc,
		predPc: ppcDP,
		eEpoch: f2d.eEpoch,
		dInst: dInst,
		inst: inst,
		brDir: bht.getDirectionBits(f2d.pc) 
	    };
	    d2rFifo.enq(d2r);
	end
    endrule

    rule doReg(csrf.started);
	let d2r = d2rFifo.first;

	// reg read
	Data rVal1 = rf.rd1(fromMaybe(?, d2r.dInst.src1));
	Data rVal2 = rf.rd2(fromMaybe(?, d2r.dInst.src2));
	Data csrVal = csrf.rd(fromMaybe(?, d2r.dInst.csr));
	
	// check if bad instruction
	if (d2r.eEpoch == eEpoch[1]) begin
	    Reg2Exec r2e = Reg2Exec {
	    	pc: d2r.pc,
	    	predPc: d2r.predPc,
	    	dInst: d2r.dInst,
	    	rVal1: rVal1,
	    	rVal2: rVal2,
	    	csrVal: csrVal,
	    	eEpoch: d2r.eEpoch,
	    	brDir: d2r.brDir
	    };
	    // search scoreboard to determine stall
	    if(!sb.search1(d2r.dInst.src1) && !sb.search2(d2r.dInst.src2)) begin
		// enq & update PC, sb
		r2eFifo.enq(r2e);
		stall[0] <= False;
		sb.insert(d2r.dInst.dst);
		d2rFifo.deq;
		$display("Register Fetch: PC = %x, inst = %x, expanded = ", d2r.pc, d2r.inst, showInst(d2r.inst));
	    end else begin
		stall[0] <= True;
		$display("Register Fetch Stalled: PC = %x", d2r.pc);
	    end
	end else begin
	    stall[0] <= False;
	    d2rFifo.deq;
	    $display("killed instruction %x in reg fetch", d2r.pc);
	end
    endrule

    // ex, mem, wb stage
    rule doExecute(csrf.started);
	r2eFifo.deq;
	let r2e = r2eFifo.first;

	// execute
	ExecInst eInst = exec(r2e.dInst, r2e.rVal1, r2e.rVal2, r2e.pc, r2e.predPc, r2e.csrVal);  

	let killed = r2e.eEpoch != eEpoch[0];
	if(killed) begin
	    $display("Execute: Killing poisoned instruction with pc = %x", r2e.pc);
	end else begin
	    // check mispred: with proper BTB, it is only possible for branch/jump inst
	    if(eInst.mispredict) begin
		$display("Execute finds misprediction: PC = %x, nextPC = %x (predicted %x)", r2e.pc,  eInst.addr, r2e.predPc);
		// only don't update btb if not sure branch switching directions
		let updateBtb = (r2e.dInst.iType == Br) ? r2e.brDir[0] == r2e.brDir[1] : True;
		pcReg[0] <= eInst.addr;
		eEpoch[0] <= !eEpoch[0]; // flip eEpoch
                if (updateBtb) begin
		    btbUpdate[0] <= Valid (BtbUpdate {
			pc: r2e.pc,
			nextPc: eInst.addr
		    });
                end
		$display("Fetch: Mispredict found during execution, pc redirected to %x", eInst.addr);
		end else begin
		    $display("Execute: PC = %x", r2e.pc);
		end
	    end

	    // train bht no matter what
	    if (r2e.dInst.iType == Br) begin
		bhtUpdate[0] <= Valid (BhtUpdate {
		pc: r2e.pc,
		taken: eInst.brTaken
	    });
 	end

	Exec2Mem e2m = Exec2Mem {
	    pc: r2e.pc,
	    dInst: r2e.dInst,
	    eEpoch: r2e.eEpoch,
	    killed: killed,
	    eInst: eInst
	};
	e2mFifo.enq(e2m);
    endrule

    rule doMem(csrf.started);
	e2mFifo.deq;
	let e2m = e2mFifo.first;
	let eInst = e2m.eInst;
	let rid <- memReqIDGen.getID;

	if (!e2m.killed) begin
	    $display("MEM: running for %x", e2m.pc);
	    // memory
	    if(eInst.iType == Ld) begin
			dCache.req(MemReq{op: Ld, addr: eInst.addr, data: ?, rid: rid});
	    end else if(eInst.iType == St) begin
			dCache.req(MemReq{op: St, addr: eInst.addr, data: eInst.data, rid: rid});
	    end else if(eInst.iType == Lr) begin
			dCache.req(MemReq{op: Lr, addr: eInst.addr, data:?, rid: rid});
		end else if(eInst.iType == Sc) begin
			dCache.req(MemReq{op: Sc, addr: eInst.addr, data: eInst.data, rid: rid});
		end
	    // check unsupported instruction at commit time. Exiting
	    if(eInst.iType == Unsupported) begin
		$fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", e2m.pc);
		$finish;
	    end
	end else begin
	    $display("MEM: killed %x", e2m.pc);
	end

	Mem2WB m2w = Mem2WB {
	    eInst: eInst,
	    pc: e2m.pc,
	    killed: e2m.killed
	};
	m2wFifo.enq(m2w);
    endrule

    rule doWB(csrf.started);
	m2wFifo.deq;
	let m2w = m2wFifo.first;
	let eInst = m2w.eInst;

	// remove from scoreboard
	sb.remove;

	if (!m2w.killed) begin
	    $display("WRITE BACK pc %x", m2w.pc);
	    // write back to reg file
	    if (eInst.iType == Ld || eInst.iType == Lr || eInst.iType == Sc) begin
		eInst.data <- dCache.resp;
	    end	
	    if(isValid(eInst.dst)) begin
		rf.wr(fromMaybe(?, eInst.dst), eInst.data);
	    end
	    csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
	end else begin
	    $display("WRITE BACK: killed PC %x", m2w.pc);
	end
    endrule

    interface MessageGet toParent = toMessageGet(toParentQ);
    interface MessagePut fromParent = toMessagePut(fromParentQ);

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Bool cpuToHostValid = csrf.cpuToHostValid;

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
        csrf.start;
        pcReg[0] <= startpc;
    endmethod

endmodule

