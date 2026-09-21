import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.address.AddressSet;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class LoadBlitzModule extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String modDir = a[0]; String outDir = a[1];
        long base = Long.parseLong(a[2].replace("0x",""), 16);
        byte[] code = Files.readAllBytes(Paths.get(modDir, "module.bin"));
        Address start = toAddr(base);
        Memory mem = currentProgram.getMemory();
        MemoryBlock blk = mem.createInitializedBlock("blitz_module", start, code.length, (byte)0, monitor, false);
        blk.putBytes(start, code);
        blk.setExecute(true); blk.setRead(true); blk.setWrite(true);
        SymbolTable st = currentProgram.getSymbolTable();
        List<String> funcs = new ArrayList<>();
        for (String line : Files.readAllLines(Paths.get(modDir, "symbols.txt"))) {
            String[] p = line.trim().split("\\s+");
            Address addr = toAddr(Long.parseLong(p[0], 16));
            String name = p[1];
            st.createLabel(addr, name, SourceType.USER_DEFINED);
            if (name.startsWith("_f") || name.equals("__MAIN")) funcs.add(line);
        }
        for (String line : funcs) {
            String[] p = line.trim().split("\\s+");
            Address addr = toAddr(Long.parseLong(p[0], 16));
            new DisassembleCommand(addr, null, true).applyTo(currentProgram, monitor);
            new CreateFunctionCmd(p[1], addr, null, SourceType.USER_DEFINED).applyTo(currentProgram, monitor);
        }
        analyzeChanges(currentProgram);
        new File(outDir).mkdirs();
        DecompInterface ifc = new DecompInterface();
        ifc.setOptions(new DecompileOptions());
        ifc.openProgram(currentProgram);
        int n = 0;
        PrintWriter index = new PrintWriter(new FileWriter(outDir + "/INDEX.txt"));
        FunctionManager fm = currentProgram.getFunctionManager();
        for (Function f : fm.getFunctions(true)) {
            if (!blk.contains(f.getEntryPoint())) continue;
            DecompileResults res = ifc.decompileFunction(f, 180, monitor);
            index.println(f.getName() + " " + f.getEntryPoint() + " " + f.getBody().getNumAddresses());
            if (res == null || !res.decompileCompleted()) continue;
            try (PrintWriter pw = new PrintWriter(new FileWriter(outDir + "/" + f.getName() + ".c"))) {
                pw.print(res.getDecompiledFunction().getC());
            }
            n++;
        }
        index.close();
        println("Decompiled " + n + " module functions");
    }
}
