# Projektant na PC (Windows)

Ta sama aplikacja Flutter działa na Windows jako narzędzie do **projektowania
obszarów do wytyczenia** (np. podjazdu) na wygodnym ekranie z myszą. Projekt
zapisujesz do pliku i wczytujesz na telefonie, gdzie tyczysz wygenerowane punkty.

Projektowanie nie wymaga GPS/RTK — odbiornik jest potrzebny dopiero w terenie.

## Uruchomienie

```powershell
cd app
flutter run -d windows        # albo: flutter build windows  → uruchom exe z build\windows\...
```

## Workflow

1. **Wczytaj budynek.** Włącz warstwę `Budynki (KIEG)` (przycisk warstw, prawy
   górny róg), przytrzymaj lewy przycisk myszy na budynku → „Wczytaj budynek
   tutaj". Wymaga internetu (dane z ULDK GUGiK).
2. **Zaprojektuj.** Menu ⋮ → „Budynki" → przy budynku ikona ekierki
   („Zaprojektuj"). Na ekranie konstrukcji:
   - kliknij krawędź na mapie (lub wybierz z listy „Krawędź"),
   - wybierz narzędzie: linia równoległa / prostopadła / **prostokąt (podjazd)** /
     punkty wzdłuż / przedłużenie,
   - ustaw parametry w metrach (np. podjazd: odsunięcie, długość, szerokość).
   Podgląd punktów i figury aktualizuje się na żywo.
3. **Eksport projektu.** Ikona udostępniania na pasku narzędzi → plik
   `projekt.geojson` (GeoJSON z rolami `reference`/`construction`/`stakeout`,
   współrzędne WGS84). Zapisz na dysk.
4. **Przenieś na telefon** (dysk / e‑mail / chmura).
5. **Tyczenie na telefonie.** Menu ⋮ → „Wczytaj projekt" → wskaż plik `.geojson`
   → aplikacja prowadzi do kolejnych punktów (strzałka/tarcza), a pomiary
   eksportujesz w CSV/GeoJSON (WGS84 + PL‑2000).

Projekt można też zrobić w całości na telefonie (te same ekrany) — PC tylko
ułatwia rysowanie na większym ekranie.
