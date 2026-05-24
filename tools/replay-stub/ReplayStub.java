import java.io.*;
import java.util.*;
import java.util.regex.*;

/**
 * Fake replay stub for sh.bang e2e tests.
 *
 * Usage:
 *   java -jar replay-stub.jar --rdat <file> --filter "tradeId in (A,B,C)"
 *
 * Reads the rdat file line by line (each line = one tradeId).
 * Prints "Replayed <id>" or "Skipped <id>" based on the filter list.
 */
public class ReplayStub {

    public static void main(String[] args) throws Exception {
        String rdatFile = null;
        String filter   = null;

        for (int i = 0; i < args.length - 1; i++) {
            if ("--rdat".equals(args[i]))   rdatFile = args[i + 1];
            if ("--filter".equals(args[i])) filter   = args[i + 1];
        }

        if (rdatFile == null || filter == null) {
            System.err.println("Usage: replay-stub.jar --rdat <file> --filter \"tradeId in (A,B,C)\"");
            System.exit(1);
        }

        Set<String> allowed = parseFilter(filter);

        System.out.println("[replay-stub] rdat:   " + rdatFile);
        System.out.println("[replay-stub] filter: " + filter);
        System.out.println("[replay-stub] ids:    " + allowed);
        System.out.println();

        try (BufferedReader br = new BufferedReader(new FileReader(rdatFile))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;
                if (allowed.contains(line)) {
                    System.out.println("Replayed " + line);
                } else {
                    System.out.println("Skipped  " + line);
                }
            }
        }

        System.out.println();
        System.out.println("[replay-stub] done.");
    }

    /** Parse "tradeId in (A, B, C)" → Set{"A","B","C"} */
    private static Set<String> parseFilter(String filter) {
        Set<String> ids = new LinkedHashSet<>();
        Matcher m = Pattern.compile("\\(([^)]+)\\)").matcher(filter);
        if (m.find()) {
            for (String id : m.group(1).split(",")) {
                ids.add(id.trim());
            }
        }
        return ids;
    }
}
