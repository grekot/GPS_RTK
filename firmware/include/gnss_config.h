#pragma once
// =============================================================================
// gnss_config — konfiguracja modułu LC29HEA przy starcie (M8, opcjonalna).
// Aktywna tylko gdy ENABLE_GNSS_CONFIG=1. Bez tego funkcja jest pustym no-op,
// a most działa w pełni przezroczyście (moduł zachowuje ustawienia fabryczne).
// =============================================================================

void gnssConfigApply();
