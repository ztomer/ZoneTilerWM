// ConfigValidator.swift — semantic validation of a loaded config (port of the intent of
// config_validator.lua, adapted: TOML/Codable decoding already guarantees types/shape, so
// this checks the remaining semantic constraints). Returns a list of problems ([] = valid).

import ZTCore

public enum ConfigValidator {
    public static func validate(_ cfg: ConfigLoader.LoadedConfig) -> [String] {
        var errors: [String] = []

        if cfg.aliases["HYPER"] == nil {
            errors.append("Missing 'aliases.HYPER' modifier alias")
        }
        if cfg.zoneConfig.grids.isEmpty {
            errors.append("Missing 'tiler.grids'")
        }
        for (key, grid) in cfg.zoneConfig.grids where grid.cols < 1 || grid.rows < 1 {
            errors.append("Invalid grid 'tiler.grids.\(key)': cols/rows must be >= 1")
        }
        if cfg.zoneConfig.layouts.isEmpty {
            errors.append("Missing 'tiler.layouts'")
        }
        if let margins = cfg.zoneConfig.margins, margins.size < 0 {
            errors.append("'tiler.margins.size' must be >= 0")
        }
        return errors
    }

    public static func isValid(_ cfg: ConfigLoader.LoadedConfig) -> Bool {
        validate(cfg).isEmpty
    }
}
