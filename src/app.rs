//! HTTP application: route definitions and handlers, kept separate from `main`
//! so the router can be exercised directly in tests without binding a socket.

use std::sync::OnceLock;
use std::time::Duration;

use axum::http::StatusCode;
use axum::{Json, Router, routing::get};
use axum_prometheus::PrometheusMetricLayer;
use axum_prometheus::metrics_exporter_prometheus::PrometheusHandle;
use serde::Serialize;
use tower_http::{timeout::TimeoutLayer, trace::TraceLayer};

/// Requests are aborted after this long, guarding against slow or stuck handlers.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Serialize)]
struct ServiceInfo {
    name: &'static str,
    version: &'static str,
}

/// The Prometheus recorder is process-global, so build it exactly once even
/// though `app()` is called repeatedly (once per test, plus `main`).
fn metric_layer_and_handle() -> &'static (PrometheusMetricLayer<'static>, PrometheusHandle) {
    static PAIR: OnceLock<(PrometheusMetricLayer<'static>, PrometheusHandle)> = OnceLock::new();
    PAIR.get_or_init(PrometheusMetricLayer::pair)
}

/// Builds the application router. Shared by `main` (real server) and integration tests.
pub fn app() -> Router {
    let (prometheus_layer, metric_handle) = metric_layer_and_handle().clone();

    Router::new()
        .route("/", get(info))
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/metrics", get(|| async move { metric_handle.render() }))
        .layer(TraceLayer::new_for_http())
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            REQUEST_TIMEOUT,
        ))
        .layer(prometheus_layer)
}

async fn info() -> Json<ServiceInfo> {
    Json(ServiceInfo {
        name: env!("CARGO_PKG_NAME"),
        version: env!("CARGO_PKG_VERSION"),
    })
}

/// Liveness probe: process is up and able to respond.
async fn healthz() -> &'static str {
    "ok"
}

/// Readiness probe: service is ready to accept traffic.
async fn readyz() -> &'static str {
    "ok"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn healthz_handler_returns_ok_body() {
        assert_eq!(healthz().await, "ok");
    }

    #[tokio::test]
    async fn readyz_handler_returns_ok_body() {
        assert_eq!(readyz().await, "ok");
    }

    #[tokio::test]
    async fn info_handler_reports_package_metadata() {
        let Json(info) = info().await;
        assert_eq!(info.name, env!("CARGO_PKG_NAME"));
        assert_eq!(info.version, env!("CARGO_PKG_VERSION"));
    }
}
