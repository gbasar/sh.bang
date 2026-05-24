import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;
import com.typesafe.config.ConfigRenderOptions;

import java.io.File;
import java.nio.file.Paths;

/**
 * Converts a HOCON file to compact JSON on stdout.
 * Usage: java -jar hocon-to-json.jar <file.hocon>
 */
public class HoconToJson {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("usage: hocon-to-json <file.hocon>");
            System.exit(1);
        }

        File file = Paths.get(args[0]).toAbsolutePath().toFile();
        if (!file.exists()) {
            System.err.println("file not found: " + file);
            System.exit(1);
        }

        Config config = ConfigFactory.parseFile(file).resolve();
        System.out.println(config.root().render(
            ConfigRenderOptions.concise().setJson(true)
        ));
    }
}
