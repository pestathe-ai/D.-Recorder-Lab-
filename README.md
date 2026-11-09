# D. Recorder Lab

Registra riunioni lunghe sul telefono, le trascrive **offline** con Whisper e
aiuta a preparare il verbale.

## Funzioni (v0.1)

- Registrazione in background con schermo spento, pausa e punti segnati.
- Salvataggio continuo: in caso di spegnimento si perdono al massimo pochi secondi.
- Archivio con ricerca, rinomina, condivisione ed eliminazione.
- Trascrizione italiana sul telefono, ripresa automatica se interrotta.
- Testo correggibile e collegato all'audio.
- Verbale a campi, esportabile in Word o testo.
- Importazione di file audio e video per trascriverli.
- Riassunto gratuito tramite un chatbot a scelta: copi il testo e incolli la risposta.

## Limiti noti

- L'audio occupa circa 115 MB all'ora (WAV 16 kHz mono).
- La trascrizione è lenta su audio lunghi e scalda il telefono.
- Non distingue chi sta parlando.
- Importa solo i formati che il telefono sa leggere.
- Il chatbot riceve il contenuto della riunione e può avere limiti sui testi lunghi.
- La trascrizione può sbagliare nomi e cifre: il verbale va sempre riletto.

## Sviluppo

Le cartelle `android/` e `ios/` sono generate da `tool/setup_platforms.sh`
durante la build su GitHub Actions.
