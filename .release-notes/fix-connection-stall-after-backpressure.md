## Fix connection stall after large response with backpressure

Connections could stop processing incoming data after completing a large response that triggered backpressure, causing the connection to hang.
