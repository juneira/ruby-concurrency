Threads em Ruby
===============

Se você está presente na comunidade Ruby a algum tempo, já deve ter ouvido falar a respeito de Threads.
Há muita confusão a respeito do tema, desde a compreensão de como as Threads funcionam no Ruby (MRI 3.0 >=),
qual o papel do GVL e quais o problemas podemos enfrentar quando usamos esse mecânismo.

O que são Threads?
==================

Segundo a própria definição na página do [ruby-doc.org](https://ruby-doc.org/core-2.5.9/Thread.html), temos que:
- Threads são a implementação do Ruby para o modelo de programação concorrente.

Ou seja, podemos executar código de forma concorrente através da Thread, onde cada uma das Threads é independente.

Por exemplo:

(hello_thread.rb)
```ruby
thr_ola = Thread.new { puts "Ola, eu sou um thread"  }
thr_oi = Thread.new { puts "Oi, eu sou um thread"  }
thr_hello = Thread.new { puts "Hello, I'm a thread"  }


# Aguarda todas as threads executarem
# (Como cada uma delas são independentes, pode ocorrer do programa finalizar antes de todas executarem)
[thr_ola, thr_oi, thr_hello].each(&:join)
```

O resultado obtido na minha máquina foi (provavelmente na sua será igual):
```
Ola, eu sou um thread
Oi, eu sou um thread
Hello, I'm a thread`
```

Aqui foi um exemplo simples, mas Threads podem executar tarefas mais complexas, como os **workers** do [Puma](https://github.com/puma/puma), onde cada requisição é atendida em uma Thread separada.

Um detalhe importante sobre Threads é que elas não rodam de forma paralela, ou seja, enquanto a Thread `thr_ola` estava rodando, nenhuma outra estava. Isso ocorre por conta do GVL!

O que é GVL?
============

GVL, ou Global VM Lock, é uma funcionalidade do Ruby (mais especificamente do CRuby - MRI Ruby).
Como o nome já diz, o "lock" existe globalmente sobre a VM do Ruby e não sobre todo o interpretador.

Isso é importante porque a VM do Ruby não é thread-safe, logo se duas threads acessarem a VM do Ruby ao mesmo tempo, muito provavelmente teremos bugs!
Logo a função do GVL é deixar apenas que uma Thread rode, enquanto as outras ficam esperando em uma fila, de forma que as Threads nunca irão rodar em paralelo.

Em resumo, para criar um VM totalmente thread-safe seria muito complexo, de forma que o GVL é necessário.

Para vermos o GVL em ação, iremos rodar o código abaixo em dois interpretadores diferentes:

(thread_gvl_test.rb)
```ruby
def test_gvl
  arr = []

  threads = 10.times.map do
    Thread.new do
      100.times do
        arr << 1 # Inserir elementos no array não é uma operação atomica!
      end
    end
  end

  threads.each(&:join)

  if arr.count != 1000
    # 10 Threads inserindo 100 elementos no array = 1000 elementos
    puts "Era esperado 1000 elementos, mas existem %d elementos" % arr.count

    return true
  end

  false
end

# É necessário rodar o teste mais de uma vez
10.times do
  break if test_gvl
end

puts "Fim do teste"
```

Testando no Ruby MRI - 3.3.5 (Com GVL) temos:
```
Fim do teste
```

Ou seja, não houve nenhum problema.

Já para o teste no JRuby - 9.4.8.0 (Sem GVL) temos:
```
Era esperado 1000 elementos, mas existem 998 elementos
Fim do teste
```

A diferença pode ser diferente quando você fizer o teste, pois as threads podem ter rodado diferente no seu teste.

Você deve estar pensando: Que diabos aconteceu aqui?
Para entendermos, temos que dar mais um passo!

O Próximo Passo - RVM
======================

Quando rodamos um código Ruby, ele é compilado para instruções RVM.
Por exemplo o código abaixo, semelhante ao trecho de código executado pelas Threads no teste anterior:

(inside_thread_gvl_test.rb)
```ruby
arr = []

# Removi a parte do loop, para facilitar a visualização
arr << 1
```

Executando o comando dump com a opção `insns` temos o seguinte resultado:

`ruby --dump=insns inside_thread_gvl_test.rb`

```
[ 1] arr@0
0000 newarray                               0                         (   1)[Li]
0002 setlocal_WC_0                          arr@0
0004 getlocal_WC_0                          arr@0                     (   3)[Li]
0006 putobject_INT2FIX_1_
0007 opt_ltlt                               <calldata!mid:<<, argc:1, ARGS_SIMPLE>[CcCr]
0009 leave
```

Não irei me aprofundar como funciona a VM (até porque eu tenho conhecimento limitado a respeito), apenas iremos utilizar a parte que realmente nos importar para solucionar o mistério do problema ocorrido na JRuby.

E para nós o que realmente importa é o comando `opt_ltlt`. Que executa a operação de inserir um valor no array, modicando ele.

Procurando nas definições dos [comandos da RVM](https://github.com/ruby/ruby/blob/master/insns.def) temos:

```c
/* << */
DEFINE_INSN
opt_ltlt
(CALL_DATA cd)
(VALUE recv, VALUE obj)
(VALUE val)
/* This instruction can append an integer, as a codepoint, into a
 * string.  Then what happens if that codepoint does not exist in the
 * string's encoding?  Of course an exception.  That's not a leaf. */
// attr bool leaf = false; /* has "invalid codepoint" exception */
{
    val = vm_opt_ltlt(recv, obj);

    if (UNDEF_P(val)) {
        CALL_SIMPLE_METHOD();
    }
}
```

Vamos agora procurar o primeiro comando `vm_opt_ltlt(recv, obj)` no [vm_insnhelper](https://github.com/ruby/ruby/blob/master/vm_insnhelper.c)

```c
static VALUE
vm_opt_ltlt(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
             BASIC_OP_UNREDEFINED_P(BOP_LTLT, STRING_REDEFINED_OP_FLAG)) {
        if (LIKELY(RB_TYPE_P(obj, T_STRING))) {
            return rb_str_buf_append(recv, obj);
        }
        else {
            return rb_str_concat(recv, obj);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(BOP_LTLT, ARRAY_REDEFINED_OP_FLAG)) {
        return rb_ary_push(recv, obj); // <-- Achamos!
    }
    else {
        return Qundef;
    }
}
```

Como nosso elemento é um Array, o retorno esse função será `rb_ary_push(recv, obj)`.
E por fim nas [definições das funções da classe Array](https://github.com/ruby/ruby/blob/master/array.c).

```c
VALUE
rb_ary_push(VALUE ary, VALUE item)
{
    long idx = RARRAY_LEN((ary_verify(ary), ary));
    VALUE target_ary = ary_ensure_room_for_push(ary, 1);
    RARRAY_PTR_USE(ary, ptr, {
        RB_OBJ_WRITE(target_ary, &ptr[idx], item);
    });
    ARY_SET_LEN(ary, idx + 1);
    ary_verify(ary);
    return ary;
}
```

Olhando para o código, temos duas macros que são chaves para solucionar o nosso mistério:

- `RARRAY_LEN` retorna o tamanho do Array
- `ARY_SET_LEN` seta o tamanho do Array

Sabendo disso fica fácil entender o problema ocorrido no JRuby!

Simulando o bug
===============

Vamos simplificar o algoritmo verdadeiro para o seguinte pseudo algoritmo:

```
func adiciona_elemento_ao_array(array, elemento)
  index = busca_o_tamanho_array(array)
  adiciona_elemento(array, index, elemento)
  seta_novo_tamanho_array(array, index + 1)
fim
```

Suponha que temos o array inicialmente vazio, e que a primeira Thread rode completamente o algoritmo.
Agora temos:

```
arr == [1]
arr.size == 1
```

A segunda Thread é selecionada para rodar, porém após ela rodar a primeira linha o sistema operacional escolhe outra Thread para rodar. Ou seja, dentro da Thread 2 `index = 1`.

Suponha que a terceira Thread rode completamente, então:

```
arr = [1, 1]
arr.size == 2
```

Então a segunda Thread é selecionada para rodar novamente:
```
arr = [1, 1]
arr.size == 2
```

Como o index dentro da Thread 2 é 1, então irá substituir o valor anterior do index 1 pelo valor 1 (que é o mesmo valor nesse caso), e irá setar o tamanho do Array para 2.

Podemos assim concluir que o GVL nos protege de todos os problemas que Threads podem causar?
A resposta é NÃO!

Problemas com Threads fora da VM
================================

Como mencionado anteriormente, o GVL apenas cuida dos problemas de Thread dentro da VM. De forma que se o problema com a Thread não ocorrer dentro da operação da VM, então ainda temos que tratar fora dela.

Vamos rodar o seguinte código dentro do Ruby MRI - 3.3.5:

(thread_unsafe.rb)
```ruby
require 'thread'

# Variável compartilhada entre threads
counter = 0

# Cria múltiplas threads que incrementam o contador
threads = 10.times.map do
  Thread.new do
    1000.times do
      current_value = counter
      sleep(0.0001) # Simula IO
      counter = current_value + 1
    end
  end
end

# Esperar todas as threads terminarem
threads.each(&:join)

puts "Valor final do contador: #{counter}"
```

É esperado que o valor do contador seja **1000**, porém temos que o valor é **100**, mesmo utilizando um interpretador com GVL, visto que o problema está forá da VM!

Isso corre porque `counter` é uma região de memória compartilhada pelas Threads, e quando uma Thread estivesse alterando seu valor, outras não poderiam.
Uma boa forma de resolver esse problema é utilizando `mutex`, que assegura que somente uma Thread estará executando esse trecho de código:

(thread_safe.rb)
```ruby
require 'thread'

# Variável compartilhada entre threads
counter = 0

# Cria uma intância compartilhada do mutex
mutex = Mutex.new

# Cria múltiplas threads que incrementam o contador
threads = 10.times.map do
  Thread.new do
    1000.times do
      mutex.synchronize do
        current_value = counter
        sleep(0.0001) # Simula IO
        counter = current_value + 1
      end
    end
  end
end

# Espera todas as threads terminarem
threads.each(&:join)

puts "Valor final do contador: #{counter}"
# => Valor final do contador: 10000
```

Dessa forma resolvemos o problema, retornando o valor correto!

Deu um trabalhinho, não é mesmo?

Conclusão
=========

**Threads** resolvem nossos problemas quando temos uma carga de I/O muito grande em nossas aplicações, porém são bem complexas de trabalhar, podendo trazer bastante problema se não forem bem utilizadas.
Como uma alternativa bastante interessante, para o Ruby 3 temos o [**Async**](https://github.com/socketry/async), que irei trazer em um próximo artigo!
