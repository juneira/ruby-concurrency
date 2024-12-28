thr_ola = Thread.new { puts "Ola, eu sou um thread"  }
thr_oi = Thread.new { puts "Oi, eu sou um thread"  }
thr_hello = Thread.new { puts "Hello, I'm a thread"  }


# Aguarda todas as threads executarem
# (Como cada uma delas são independentes, pode ocorrer do programa finalizar antes de todas executarem)
[thr_ola, thr_oi, thr_hello].each(&:join)
