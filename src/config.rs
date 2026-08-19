//! Small, pure helpers kept out of `main` so they're unit-testable without
//! touching real process environment variables (which are process-global and
//! would make parallel `cargo test` runs flaky).

const DEFAULT_PORT: u16 = 8080;

/// Parses the `PORT` env var, falling back to [`DEFAULT_PORT`] if it's unset,
/// empty, or not a valid `u16`.
pub fn port_from_env(value: Option<&str>) -> u16 {
    value.and_then(|p| p.parse().ok()).unwrap_or(DEFAULT_PORT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_when_unset() {
        assert_eq!(port_from_env(None), DEFAULT_PORT);
    }

    #[test]
    fn parses_valid_value() {
        assert_eq!(port_from_env(Some("3000")), 3000);
    }

    #[test]
    fn falls_back_on_empty_value() {
        assert_eq!(port_from_env(Some("")), DEFAULT_PORT);
    }

    #[test]
    fn falls_back_on_non_numeric_value() {
        assert_eq!(port_from_env(Some("not-a-port")), DEFAULT_PORT);
    }

    #[test]
    fn falls_back_on_out_of_range_value() {
        assert_eq!(port_from_env(Some("70000")), DEFAULT_PORT);
    }
}
