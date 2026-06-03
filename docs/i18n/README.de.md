# Board-Man

[English](../../README.md) / [ja](README.ja.md) / [zh-CN](README.zh-CN.md) / [es](README.es.md) / [pt-BR](README.pt-BR.md) / [ko](README.ko.md) / [de](README.de.md) / [fr](README.fr.md)

Board-Man ist eine macOS-Produktivitätsapp für die Zwischenablage, abgeleitet von Clipy.

Sie hält den Verlauf der Zwischenablage über die Menüleiste verfügbar und bietet arbeitsablauforientierte Übersicht für Menschen, die häufig Text, URLs, Befehle und Bilder zwischen Apps kopieren, einfügen, bearbeiten und verschieben.

> Status: öffentlicher Kandidat. Dieses Repository ist eine bereinigte Open-Source-Edition, die aus einem aktiv entwickelten privaten Build vorbereitet wurde.

## Screenshot

![Board-Man main screenshot](../assets/board-man-main-screenshot.png)

## Was Board-Man kann

- Den aktuellen Verlauf der Zwischenablage über die Menüleiste verfügbar halten.
- Wiederverwendbare Snippets speichern und einfügen.
- Einfügezähler-Badges für häufig verwendete Elemente anzeigen.
- Bildeinträge der Zwischenablage verarbeiten, einschließlich bildreiner Inhalte wie Screenshots.
- Den Verlauf der Zwischenablage durchsuchen.
- Das Panel per Tastatur bedienen.
- Wichtige Elemente anheften.
- Kurzbefehle, Verlaufslimits, Menüverhalten und visuelle Designoptionen anpassen.
- Lokal auf macOS laufen, ohne Inhalte der Zwischenablage an einen externen Dienst zu senden.

## Download

- [Board-Man v1.2.3 herunterladen](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- macOS-App-Archiv: `Board-Man-v1.2.3.zip`

## Installation und erster Start

1. Lade `Board-Man-v1.2.3.zip` von der Release-Seite herunter.
2. Entpacke das Archiv.
3. Verschiebe `Board-Man.app` nach `/Applications`.
4. Öffne Board-Man.

Wenn macOS Gatekeeper den ersten Start blockiert, öffne **System Settings > Privacy & Security** und erlaube Board-Man, oder führe Control-click auf die App aus und wähle **Open**.

## Grundlegende Nutzung

1. Kopiere wie gewohnt Text, eine URL, einen Befehl oder ein Bild.
2. Öffne Board-Man über die Menüleiste.
3. Suche oder bewege dich durch den Verlauf der Zwischenablage.
4. Wähle ein Element aus, um es in die aktive App einzufügen.
5. Verwende Snippets für Text, den du wiederholt einfügst.

## Verlauf der Zwischenablage

Board-Man speichert aktuelle Elemente der Zwischenablage, sodass du zu Texten, URLs, Befehlen und Bildeinträgen zurückkehren kannst, ohne sie erneut zu kopieren.

Nutze dies, wenn du:

- etwas zuvor Kopiertes wiederverwenden möchtest
- nicht nur zum erneuten Kopieren desselben Textes zwischen Dokumenten wechseln möchtest
- aktuelle Befehle oder URLs griffbereit halten möchtest
- den Ablauf kopier- und einfügeintensiver Arbeit nachvollziehen möchtest

## Snippets

Snippets sind wiederverwendbare Texteinträge für Formulierungen, Vorlagen, URLs, Befehle und andere Inhalte, die du häufig einfügst.

Typische Verwendungen:

- wiederholte Antworten
- Befehlsvorlagen
- Marketing- oder Social-Media-Textblöcke
- Supportnachrichten
- URLs und kurze Textbausteine

## Einfügezähler-Badges

Einfügezähler-Badges zeigen, wie oft ein Element eingefügt wurde.

Das hilft dir zu erkennen:

- Text, den du häufig wiederverwendest
- Befehle, die du wiederholt ausführst
- Assets oder Snippets, die für deinen Workflow zentral sind
- Kopier-/Einfügemuster, die sich als Snippets oder Automatisierung lohnen könnten

## Unterstützung für Bilder in der Zwischenablage

Board-Man unterstützt Bildeinträge der Zwischenablage und kann bildreine Inhalte im Verlauf anzeigen.

Das ist nützlich beim Kopieren von:

- Screenshots
- Grafiken
- Designreferenzen
- visuellen Zwischenablageinhalten zwischen Apps

Bildeinträge verwenden eine zeitstempelbasierte Identität, damit generische Namen wie `TIFF image` oder `PNG image` bei den Einfügezählern nicht kollidieren.

## Suche und Tastaturnavigation

Nutze die Suche, um den Verlauf der Zwischenablage zu filtern. Das Panel ist für tastaturgesteuerte Nutzung ausgelegt, damit du suchen, durch Ergebnisse navigieren und einfügen kannst, ohne den aktuellen Workflow zu verlassen.

## Einstellungen und Darstellung

Board-Man enthält Einstellungen für Menüverhalten, Kurzbefehle, Verlaufslimits und visuelle Darstellung. Je nach aktuellem Build kannst du Design- und hellere Anzeigeoptionen verwenden, um das Panel leichter lesbar zu machen.

## Datenschutz

Board-Man ist ein lokales macOS-Werkzeug. Inhalte der Zwischenablage werden lokal von der App verarbeitet. Speichere keine Secrets, Tokens, Passwörter oder privaten Kundendaten im Verlauf der Zwischenablage, es sei denn, du verstehst das Risiko.

## Lizenz und Attribution

Board-Man ist ein stark verändertes abgeleitetes Werk auf Basis von Clipy.

Dieses Repository bewahrt die Attribution und Lizenzhinweise des Upstream-Projekts:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

Board-Man wird unter den von Clipy geerbten MIT-Lizenzbedingungen verteilt. Es wird nicht von den Upstream-Maintainern von Clipy oder ClipMenu unterstützt.
