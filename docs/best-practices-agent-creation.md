# Best Practices: Agent-Erstellung

Dieses Dokument ist die verbindliche Referenz für das Erstellen neuer Agents im Agent-Context-Projekt.

---

## 1. Grundprinzipien

### Simplicity First
Ein Agent löst genau eine klar abgrenzbare Aufgabe. Wenn die Beschreibung mehr als zwei Sätze braucht, ist der Scope wahrscheinlich zu breit.

### Focused Scope
Agents sind keine Allzweck-Assistenten. Je enger der Scope, desto präziser das Routing und desto besser die Ausgabe. Zwei spezialisierte Agents schlagen einen generalistischen Agent.

### Evidence Over Assumption
Agents lesen zuerst Projektkontext (`.agent-context/`-Dateien, `package.json`, `composer.json` etc.), bevor sie Annahmen über das Tech-Stack treffen. Ohne Kontext nachfragen oder explorieren — nie raten.

---

## 2. Frontmatter-Design

### Pflichtfelder

```yaml
---
name: ac-beispiel
description: "Kurze Beschreibung. Delegates here for X, Y, Z. Use when doing A or B."
tools: Read, Glob, Grep, Bash
model: sonnet
maxTurns: 20
effort: normal
---
```

| Feld | Beschreibung |
|------|-------------|
| `name` | Kebab-case, beginnt mit Projekt-Präfix (`ac-`) |
| `description` | Trigger-Text für automatisches Routing (siehe unten) |
| `tools` | Nur tatsächlich benötigte Tools — keine Defaults |
| `model` | `opus` / `sonnet` / `haiku` (siehe Tabelle unten) |
| `maxTurns` | Realistisches Maximum; zu hoch = Kosten, zu niedrig = Abbruch |
| `effort` | `low` / `normal` / `high` — beeinflusst Token-Budget |

### Optionale Felder

| Feld | Wann sinnvoll |
|------|--------------|
| `memory: project` | Agent braucht persistenten Projektspeicher |
| `mcpServers` | Agent benötigt spezifische MCP-Server |
| `initialPrompt` | Vorab-Instruktionen vor dem eigentlichen Task |

### Description Design

Die `description` ist das wichtigste Feld für automatisches Routing. Der Text muss klar kommunizieren, *wann* dieser Agent gerufen werden soll.

**Gut:**
```yaml
description: "Backend development specialist. Delegates here for server-side code,
  APIs, database operations. Use when implementing business logic, creating endpoints,
  or modifying database schemas."
```

**Schlecht:**
```yaml
description: "Ein Agent der Backend-Sachen macht."
```

Muster für gute Descriptions:
- `"<Rolle>. Delegates here for <Aufgabentypen>. Use when <konkrete Trigger>."`
- Konkrete Keywords nennen, die beim Routing gematcht werden können
- Kein Marketingsprech — technisch und präzise

### Model-Auswahl

| Model | Wann einsetzen | Kosten/Speed |
|-------|---------------|-------------|
| `opus` | Komplexes Reasoning, Architektur-Entscheidungen, Multi-Perspektiven-Analyse | Langsam, teuer |
| `sonnet` | Klar definierte Tasks, Code-Generierung, Dokumentation | Schnell, günstig |
| `haiku` | Schnelle Read-Only-Tasks, Klassifizierung, einfache Lookups | Sehr schnell, sehr günstig |

Faustregel: Wähle das schwächste Modell, das den Task zuverlässig erfüllt.

### Tool-Minimierung

Nur Tools deklarieren, die der Agent tatsächlich verwendet. Überflüssige Tools erhöhen die Angriffsfläche und verwirren das Modell.

| Agent-Typ | Typische Tools |
|-----------|---------------|
| Read-Only (Review, Discovery) | `Read, Glob, Grep, Bash` |
| Development (Backend, Frontend) | `Read, Write, Edit, Glob, Grep, Bash` |
| Research | `Read, Glob, Grep, Bash, WebFetch, WebSearch` |
| Browser-Automatisierung | `Read, Glob, Grep, Bash, Write` + MCP-Tools |

Das `Agent`-Tool nur für Agents verwenden, die explizit Sub-Agents dispatchen (z.B. `ac-review` für parallele Review-Perspektiven).

---

## 3. Prompt-Struktur

### Konsistente Sektionen

Alle Agents folgen dieser Grundstruktur:

```markdown
# <Agent-Name>

<Einzeiler: Rolle und Hauptaufgabe.>
Respond in the user's language.

## Role
<Ausführliche Rollenbeschreibung mit Scope>

## Core Principle
**<Kernregel in Bold.>** <Erklärung warum diese Regel wichtig ist.>

## Workflow
### 1. Kontext laden
### 2. Analyse / Planung
### 3. Ausführung
### 4. Quality Gate

## Output Format
<Erwartetes Ausgabeformat, ggf. Markdown-Vorlage>

## Rules
<Wenige, harte Regeln — nur was wirklich erzwungen werden muss>
```

Die Reihenfolge Role → Core Principle → Workflow → Output Format → Rules ist bewährt: Das Modell versteht zuerst *wer* es ist, dann *wie* es vorgeht, dann *was* es liefern soll, dann *was nie*.

### Affirmative Formulierung

Positive Instruktionen sind präziser und werden besser befolgt als Verbote.

**Bevorzugen:**
```markdown
- Use the project's ORM/DAL for all database queries
- Ask for clarification when requirements are ambiguous
```

**Vermeiden:**
```markdown
- Never use raw SQL unless explicitly required
- Don't guess what the user wants
```

`NEVER` und `ALWAYS` in Großbuchstaben nur für harte Sicherheitsregeln reservieren (z.B. "NEVER modify production data directly"). Aggressive Sprache wie "CRITICAL: YOU MUST" reduziert die Qualität — Claude 4.x reagiert besser auf ruhige, sachliche Instruktionen.

### Konsistente Terminologie

Innerhalb eines Agents einheitliche Begriffe verwenden. Nicht abwechselnd "task", "job", "request" und "Aufgabe" — einen Begriff wählen und durchhalten.

---

## 4. Context Engineering

### Progressive Disclosure

Kontext in Schichten laden — nur was für den aktuellen Schritt gebraucht wird:

1. Bootstrap-Kontext (Tech-Stack, Umgebung) → immer laden
2. Projektregeln (Conventions, Patterns) → für Implementierungsaufgaben laden
3. Domänen-Kontext (spezifische Module, Entscheidungen) → bei Bedarf nachladen

### Just-in-Time Retrieval

Nicht alles am Anfang laden. Spezialisierte Kontext-Dateien (z.B. `memory/architecture.md`) erst abrufen, wenn der Agent sie tatsächlich braucht. Das reduziert Token-Verbrauch und hält den Kontext fokussiert.

### Graceful Fallback für `.agent-context/`-Dateien

`.agent-context/`-Dateien sind optional. Agents müssen mit ihrer Abwesenheit umgehen können:

```markdown
### 1. Kontext laden
- Lade `.agent-context/layer1-bootstrap.md` → Tech-Stack, Umgebung
- Lade `.agent-context/layer2-project-core.md` → Conventions, Regeln
- Falls nicht vorhanden: Erkenne Tech-Stack aus `package.json`, `composer.json`,
  `go.mod`, `requirements.txt` etc.
```

Kein harter Fehler, wenn Dateien fehlen — alternativ explorieren.

---

## 5. Workflow-Design

### Stopping Conditions

Jeder Workflow-Schritt sollte eine klare Abschlussbedingung haben. Agents, die nicht wissen wann sie fertig sind, iterieren unnötig oder brechen zu früh ab.

Beispiel: "Schritt gilt als abgeschlossen, wenn alle Tests grün sind und der QA-Command ohne Fehler durchläuft."

### Error Recovery

Fehlerbehandlung explizit beschreiben:
- Was tun, wenn eine Datei nicht gefunden wird?
- Was tun, wenn ein Command fehlschlägt?
- Wann den Nutzer um Klärung bitten vs. selbst entscheiden?

### MCP-Tool-Referenzen als "if available"

MCP-Tools sind nicht in jedem Kontext verfügbar. Stets bedingt formulieren:

```markdown
Use documentation MCP tools if available (e.g., context7) for framework lookups.
Use IDE MCP tools if available (e.g., JetBrains) for symbol search.
```

Nicht: "Verwende context7 für alle Framework-Fragen." — das schlägt fehl, wenn der Server nicht aktiv ist.

---

## 6. Anti-Patterns

### Architektur

| Anti-Pattern | Problem | Lösung |
|---|---|---|
| Multi-Agent für einfache Tasks | Overhead ohne Mehrwert | Unter 3 Tool-Calls: kein Sub-Agent |
| Agent als Wrapper ohne Eigenlogik | Unnötige Indirektion | Direkten Agent implementieren oder zusammenführen |
| Zu breiter Scope ("macht alles") | Schlechtes Routing, inkonsistente Ausgabe | Scope auf eine Domäne begrenzen |

### Instruktionen

| Anti-Pattern | Problem | Lösung |
|---|---|---|
| Inkonsistente Terminologie | Verwirrung, unvorhersehbares Verhalten | Einen Begriff pro Konzept — durchgängig |
| Aggressive Sprache ("CRITICAL: YOU MUST") | Reduzierte Ausgabequalität | Ruhige, sachliche Formulierungen |
| Widersprüchliche Regeln | Modell wählt willkürlich | Explizite Prioritäten definieren |
| Keine Output-Format-Definition | Inkonsistente, schwer parsbare Ausgaben | Immer ein Ausgabeformat angeben |

### Tools

| Anti-Pattern | Problem | Lösung |
|---|---|---|
| Zu breite Tool-Listen | Erhöhte Angriffsfläche, Ablenkung | Minimal-Set pro Agent-Typ (siehe §2) |
| `Write`/`Edit` bei Read-Only-Agents | Sicherheitsrisiko | Explizit nur Read-Tools deklarieren |
| `Agent`-Tool ohne Dispatch-Logik | Ungenutzter Overhead | Nur wenn Sub-Agents tatsächlich dispatched werden |

### Output

| Anti-Pattern | Problem | Lösung |
|---|---|---|
| Kein Output Format definiert | Jeder Run liefert andere Struktur | Markdown-Vorlage im Prompt definieren |
| Zu detaillierter Output für einfache Tasks | Rauschen, schwer nutzbar | Output-Länge dem Task-Typ anpassen |
| Kein Summary am Ende | Nutzer muss Ausgabe selbst interpretieren | Immer kurze Zusammenfassung, was getan wurde |

---

## 7. Checkliste für neue Agents

Vor dem Commit eines neuen Agents alle Punkte prüfen:

### Frontmatter
- [ ] `name` in Kebab-case mit Projekt-Präfix
- [ ] `description` enthält "Delegates here for..." und "Use when..."
- [ ] `tools` auf Minimum reduziert (kein `Write`/`Edit` bei Read-Only-Agents)
- [ ] `model` dem Task angemessen (nicht reflexartig `opus`)
- [ ] `maxTurns` realistisch gesetzt (nicht 100 als Default)
- [ ] `effort` gesetzt (`low`/`normal`/`high`)

### Prompt
- [ ] Einzeiler-Rollenbeschreibung vorhanden
- [ ] `Respond in the user's language.` enthalten
- [ ] Sektionen: Role → Workflow → Output Format → Rules
- [ ] Workflow hat nummerierte Schritte mit klaren Abschlussbedingungen
- [ ] Graceful Fallback für fehlende `.agent-context/`-Dateien
- [ ] MCP-Tool-Referenzen mit "if available" bedingt formuliert
- [ ] Output Format mit Markdown-Vorlage oder Beschreibung definiert

### Qualität
- [ ] Keine widersprüchlichen Regeln
- [ ] Konsistente Terminologie im gesamten Dokument
- [ ] Keine aggressive Sprache außer für harte Sicherheitsregeln
- [ ] Affirmative statt negative Formulierungen wo möglich
- [ ] Agent ist in `.claude/agents/` oder `agents/` abgelegt

### Test
- [ ] Agent manuell mit einem repräsentativen Task getestet
- [ ] Scope klar genug, dass Routing korrekt funktioniert

---

## 8. Quellen

### Anthropic

- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — Grundlagen-Paper zu Agent-Design-Prinzipien
- [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Progressive Disclosure, Just-in-Time Retrieval
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — Parallelisierung und Orchestrierung
- [Claude Code Sub-Agents Docs](https://code.claude.com/docs/en/sub-agents) — Frontmatter-Referenz, Tool-Liste
- [Claude 4 Prompt Engineering Best Practices](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) — Affirmative Instruktionen, Tone

### Community

- [Writing a Good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md) — Strukturierung von Instruktionsdokumenten
- [Agent Instruction Patterns and Anti-Patterns](https://elements.cloud/blog/agent-instruction-patterns-and-antipatterns-how-to-build-smarter-agents/) — Anti-Pattern-Katalog
- [State of Agent Engineering](https://www.langchain.com/state-of-agent-engineering) — Überblick über aktuelle Patterns und Trends
