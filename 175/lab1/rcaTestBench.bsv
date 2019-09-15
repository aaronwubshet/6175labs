diff --git a/Makefile b/Makefile
index c922505..d94f631 100644
--- a/Makefile
+++ b/Makefile
@@ -5,6 +5,9 @@ compile:
 mux: compile
 	bsc -sim -e mkTbMux -bdir buildDir -info-dir buildDir -simdir buildDir -o simMux buildDir/*.ba
 
+mux1: compile
+	bsc -sim -e mkTb1Mux -bdir buildDir -info-dir buildDir -simdir buildDir -o simMux1 buildDir/*.ba
+
 muxsimple: compile
 	bsc -sim -e mkTbMuxSimple -bdir buildDir -info-dir buildDir -simdir buildDir -o simMuxSimple buildDir/*.ba
 
@@ -23,7 +26,7 @@ csasimple: compile
 bs: compile
 	bsc -sim -e mkTbBS -bdir buildDir -info-dir buildDir -simdir buildDir -o simBs buildDir/*.ba
 
-all: mux muxsimple rca rcasimple csa csasimple bs
+all: mux mux1 muxsimple rca rcasimple csa csasimple bs
 
 clean:
 	rm -rf buildDir sim*
diff --git a/TestBench.bsv b/TestBench.bsv
index 8427fe1..6c55590 100644
--- a/TestBench.bsv
+++ b/TestBench.bsv
@@ -71,6 +71,36 @@ module mkTbMux();
         cycle <= cycle + 1;
     endrule
 endmodule
+(* synthesize *)
+module mkTb1Mux();
+    Reg#(Bit#(32)) cycle <- mkReg(0);
+    Randomize#(Bit#(1)) randomVal1 <- mkGenericRandomizer;
+    Randomize#(Bit#(1)) randomVal2 <- mkGenericRandomizer;
+    Randomize#(Bit#(1))  randomSel <- mkGenericRandomizer;
+
+    rule test;
+        if(cycle == 0) begin
+            randomVal1.cntrl.init;
+            randomVal2.cntrl.init;
+            randomSel.cntrl.init;
+        end else if(cycle == 128) begin
+            $display("PASSED");
+            $finish;
+        end else begin
+            let val1 <- randomVal1.next;
+            let val2 <- randomVal2.next;
+            let sel <- randomSel.next;
+            let test = multiplexer1(sel, val1, val2);
+            let realAns = sel == 0? val1: val2;
+            if(test != realAns) begin
+                $display("FAILED Sel %b from %d, %d gave %d instead of %d", sel, val1, val2, test, realAns);
+                $finish;
+            end
+        end
+        cycle <= cycle + 1;
+    endrule
+endmodule
+
 
 // ripple carry adder testbenches
  
