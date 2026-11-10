import AppIntents
import SwiftUI
import WidgetKit

@main
struct LifeWidgets: WidgetBundle {
    var body: some Widget {
        WidgetOggi()
        WidgetTodo()
        WidgetPromemoria()
        WidgetEventi()
        WidgetCalendario()
        WidgetFinanze()
        WidgetBloccoEvento()
        WidgetBloccoTodo()
        ControlloNuovoTask()
    }
}

struct Fornitore: TimelineProvider {
    func placeholder(in context: Context) -> VoceWidget { VoceWidget(date: Date(), dati: .esempio) }

    func getSnapshot(in context: Context, completion: @escaping (VoceWidget) -> Void) {
        completion(VoceWidget(date: Date(), dati: ClienteWidget.cache ?? .esempio))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoceWidget>) -> Void) {
        Task {
            var dati = await ClienteWidget.scarica()
            if dati == nil { dati = ClienteWidget.cache }
            let ora = Date()
            var voci = [VoceWidget(date: ora, dati: dati)]
            // Quando un evento di oggi comincia o finisce, il widget cambia da solo
            for orario in Set((dati?.eventi ?? []).flatMap { [$0.inizio, $0.fine] }.compactMap { $0 }) {
                let p = orario.split(separator: ":").compactMap { Int($0) }
                guard p.count == 2, let d = Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: ora), d > ora else { continue }
                voci.append(VoceWidget(date: d, dati: dati))
            }
            voci.sort { $0.date < $1.date }
            completion(Timeline(entries: voci, policy: .after(ora.addingTimeInterval(15 * 60))))
        }
    }
}

private extension View {
    func sfondoWidget() -> some View {
        containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

private let famiglieHome: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
private let famiglieBlocco: [WidgetFamily] = [.accessoryInline, .accessoryCircular, .accessoryRectangular]

struct WidgetOggi: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.oggi", provider: Fornitore()) { VistaOggiWidget(v: $0).sfondoWidget() }
            .configurationDisplayName("Oggi")
            .description("Eventi e task di oggi: spunta i task, tocca per aprire.")
            .supportedFamilies(famiglieHome)
    }
}

struct WidgetTodo: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.todo", provider: Fornitore()) { VistaTodoWidget(v: $0).sfondoWidget() }
            .configurationDisplayName("To do")
            .description("I task di oggi, da spuntare direttamente qui.")
            .supportedFamilies(famiglieHome)
    }
}

struct WidgetPromemoria: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.promemoria", provider: Fornitore()) { VistaPromemoriaWidget(v: $0).sfondoWidget() }
            .configurationDisplayName("Promemoria")
            .description("I task di oggi, nello stile di Promemoria.")
            .supportedFamilies(famiglieHome)
    }
}

struct WidgetEventi: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.eventi", provider: Fornitore()) { VistaEventiWidget(v: $0).sfondoWidget() }
            .configurationDisplayName("Prossimi eventi")
            .description("Cosa c'è in arrivo. Tocca un evento per aprirlo.")
            .supportedFamilies(famiglieHome)
    }
}

struct WidgetCalendario: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.calendario", provider: Fornitore()) { VistaCalendarioWidget(v: $0).sfondoWidget() }
            .configurationDisplayName("Calendario")
            .description("Il mese e i prossimi eventi.")
            .supportedFamilies(famiglieHome)
    }
}

struct WidgetFinanze: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.finanze", provider: Fornitore()) { _ in VistaFinanzeWidget().sfondoWidget() }
            .configurationDisplayName("Finanze")
            .description("Segna un'uscita o un'entrata.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetBloccoEvento: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.blocco.evento", provider: Fornitore()) { BloccoEventoWidget(v: $0).containerBackground(for: .widget) { Color.clear } }
            .configurationDisplayName("Prossimo evento")
            .description("Il prossimo evento di oggi. Tocca per aprirlo.")
            .supportedFamilies(famiglieBlocco)
    }
}

struct WidgetBloccoTodo: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "life.blocco.todo", provider: Fornitore()) { BloccoTodoWidget(v: $0).containerBackground(for: .widget) { Color.clear } }
            .configurationDisplayName("To do")
            .description("Quanti task hai oggi. Tocca per aprirli.")
            .supportedFamilies(famiglieBlocco)
    }
}

/// Il pulsante per la schermata di blocco e il Centro di Controllo.
struct ControlloNuovoTask: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "life.controllo.nuovotask") {
            ControlWidgetButton(action: ApriLifeIntent(LinkLife.nuovoTask)) {
                Label("Nuovo task", systemImage: "plus.circle")
            }
        }
        .displayName("Nuovo task")
    }
}
