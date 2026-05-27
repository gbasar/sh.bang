import com.typesafe.config.*;
import com.typesafe.config.impl.Parseable;

import java.io.File;
import java.nio.file.Paths;

/**
 * Converts a HOCON file to compact JSON on stdout.
 * Resolves include directives relative to the source file's directory.
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

        final File baseDir = file.getParentFile();

        ConfigIncluder includer = new ConfigIncluder() {
            private ConfigIncluder fallback;

            @Override
            public ConfigIncluder withFallback(ConfigIncluder fallback) {
                this.fallback = fallback;
                return this;
            }

            @Override
            public ConfigObject include(ConfigIncludeContext context, String what) {
                File included = new File(baseDir, what);
                if (included.exists()) {
                    return ConfigFactory.parseFile(included,
                        context.parseOptions()).root();
                }
                // fall back to default (classpath etc.)
                return fallback != null ? fallback.include(context, what)
                                       : ConfigFactory.empty().root();
            }
        };

        ConfigParseOptions opts = ConfigParseOptions.defaults().setIncluder(includer);
        Config config = ConfigFactory.parseFile(file, opts).resolve();
        System.out.println(config.root().render(
            ConfigRenderOptions.concise().setJson(true)
        ));
    }
}
