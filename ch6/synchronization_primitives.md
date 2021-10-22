Q: sync.Pool 中的对象以前只能存活一个 GC 周期，在增加 victim cache 之后最多可以存活两个 GC 周期，这种说法是正确的吗?
A: 我觉得这说法是对的. 使用 pool.put() 把对象放放回 local 队列.这时 GC, local 里面的所有对象都被挪到 victim 队列中.在下次 GC 如果还没有人用
那么 victim 将会被清除. 如果 victim 里面的对象在第一次 GC 之后 第二次 GC 之前被get 使用了. 这对象是有可能活很久,但是被 get 的对象已经不在 pool 里面了.

通过 atomic.Cas 实现一个锁.

```go
package toylock

import "sync/atomic"

type toyLock struct {
	sema int32
}
// semacquire 让没有抢到 锁的 g 挂起.
func semacquire() {
    gopark()	
}

// semarelease 这个函数应该处理信号量,主要是把等待的 g 唤醒.
func semarelease() {
	goready()
}

// 原子的更新 sem 的值, 如果 sema >= 1 就说明有人占了, 等于零就可以访问临界区. 这样就通过对一个数字的原子操作,来实现一个
// 简单的锁
func semaadd(val *int32, delta int32) (new int32) {
		for {
			v := *val
			if atomic.CompareAndSwapInt32(val, v, v+delta) {
				return v + delta
			}
		}
	}
	
func (tl *toyLock) Lock() {
	if semaadd(&tl.sema, 1) == 1 {
		return
	}
    semacquire()	
	
}
func (tl *toyLock) Unlock() {
	if semaadd(&tl.sema, -1) == 0 { // 将标识减去1，如果等于0，则没有其它等待者
		return
	}
    semarelease()	
	// semrelease(&tl.sema) // 唤醒其它阻塞的goroutine
}

```

# 玩一玩 litmus7
- 安装 litmus7, 直接 homebrew 安装即可.
    - 安装 OCaml. 的包管理工具 opam `brew install gpatch && brew install opam`
    - 安装 litmus7. 这个工具是 herdtool7 套件中的一个 `opam install herdtools7`
- litmus 的使用文档: http://diy.inria.fr/doc/litmus.html
    - litmus7 脚本文件. 就可以运行测试

# 既然都装了 opam 的环境, 那不写个 Ocaml 的 hello world ?
```shell
# cat hw.ml
print_string "Hello world!\n"
```
ocmal hw.ml 


litmus7 脚本:
```
X86 OOO
{ x=0; y=0; }
 P0          | P1          ;
 MOV [x],$1  | MOV [y],$1  ;
 MOV EAX,[y] | MOV EAX,[x] ;
locations [x;y;]
exists (0:EAX=0 /\ 1:EAX=0)
```

A litmus test source has three main sections:

    The initial state defines the initial values of registers and memory locations. Initialisation to zero may be omitted.
    The code section defines the code to be run concurrently — above there are two threads. Yes we know, our X86 assembler syntax is a mistake.
    The final condition applies to the final values of registers and memory locations. 

```sh
➜ litmus7 happens_before
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Results for happens_before %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
X86 awesometest

{x=0; y=0;}

 P0          | P1          ;
 MOV [x],$1  | MOV [y],$1  ;
 MOV EAX,[y] | MOV EAX,[x] ;

locations [x; y;]
exists (0:EAX=0 /\ 1:EAX=0)
Generated assembler
        ##START _litmus_P0
        movl    $1, -4(%rbx,%rcx,4)
        movl    -4(%rsi,%rcx,4), %eax
        ##START _litmus_P1
        movl    $1, -4(%rsi,%rcx,4)
        movl    -4(%rbx,%rcx,4), %eax

Test awesometest Allowed
Histogram (4 states)
5     *>0:EAX=0; 1:EAX=0; x=1; y=1;
499993:>0:EAX=1; 1:EAX=0; x=1; y=1;
499989:>0:EAX=0; 1:EAX=1; x=1; y=1;
13    :>0:EAX=1; 1:EAX=1; x=1; y=1;
Ok

Witnesses
Positive: 5, Negative: 999995
Condition exists (0:EAX=0 /\ 1:EAX=0) is validated
Hash=2d53e83cd627ba17ab11c875525e078b
Observation awesometest Sometimes 5 999995
Time awesometest 0.13

// 省略机器配置信息

Revision exported, version 7.56
Command line: litmus7 happens_before
Parameters
#define SIZE_OF_TEST 100000
#define NUMBER_OF_RUN 10
#define AVAIL 1
#define STRIDE (-1)
#define MAX_LOOP 0
/* gcc options: -Wall -std=gnu99 -fomit-frame-pointer -O2 */
/* barrier: user */
/* launch: changing */
/* affinity: none */
/* alloc: dynamic */
/* memory: direct */
/* safer: write */
/* preload: random */
/* speedcheck: no */

```
结果 log 比较重要的信息:
- 柱状图把这次模拟出现情况 和 对应次数
- 以上面的例子 0:EAX 表示 进程 0 视角 eax 寄存器的值. x y 是全局的就没有区分线程.
- 因为我们的脚本 里面写了 `exists (0:EAX=0 /\ 1:EAX=0)` 表示我们只关心这种情况 他的 Witnesses 就告诉我们我们关心的情况
在 100w 次模拟中出现了 5 次. 就这样.

# 支线任务
Learn OCaml in Y minutes
```ocaml

# let inc x = x	+ 1 ;;
val inc : int -> int = <fun>
# let a = 99 ;;
val a : int = 99

$ cat sigtest.ml
let inc x = x + 1
let add x y = x + y

let a = 1

$ ocamlc -i ./sigtest.ml
val inc : int -> int
val add : int -> int -> int
val a : int

(*** Comments ***)

(* Comments are enclosed in (* and *). It's fine to nest comments. *)

(* There are no single-line comments. *)


(*** Variables and functions ***)

(* Expressions can be separated by a double semicolon symbol, ";;".
   In many cases it's redundant, but in this tutorial we use it after
   every expression for easy pasting into the interpreter shell.
   Unnecessary use of expression separators in source code files
   is often considered to be a bad style. *)

(* Variable and function declarations use "let" keyword. *)
let x = 10 ;;

(* OCaml allows single quote characters in identifiers.
   Single quote doesn't have a special meaning in this case, it's often used
   in cases when in other languages one would use names like "foo_tmp". *)
let foo = 1 ;;
let foo' = foo * 2 ;;

(* Since OCaml compiler infers types automatically, you normally don't need to
   specify argument types explicitly. However, you can do it if
   you want or need to. *)
let inc_int (x: int) : int = x + 1 ;;

(* One of the cases when explicit type annotations may be needed is
   resolving ambiguity between two record types that have fields with
   the same name. The alternative is to encapsulate those types in
   modules, but both topics are a bit out of scope of this
   tutorial. *)

(* You need to mark recursive function definitions as such with "rec" keyword. *)
let rec factorial n =
    if n = 0 then 1
    else n * factorial (n-1)
;;

(* Function application usually doesn't need parentheses around arguments *)
let fact_5 = factorial 5 ;;

(* ...unless the argument is an expression. *)
let fact_4 = factorial (5-1) ;;
let sqr2 = sqr (-2) ;;

(* Every function must have at least one argument.
   Since some functions naturally don't take any arguments, there's
   "unit" type for it that has the only one value written as "()" *)
let print_hello () = print_endline "hello world" ;;

(* Note that you must specify "()" as argument when calling it. *)
print_hello () ;;

(* Calling a function with insufficient number of arguments
   does not cause an error, it produces a new function. *)
let make_inc x y = x + y ;; (* make_inc is int -> int -> int *)
let inc_2 = make_inc 2 ;;   (* inc_2 is int -> int *)
inc_2 3 ;; (* Evaluates to 5 *)

(* You can use multiple expressions in function body.
   The last expression becomes the return value. All other
   expressions must be of the "unit" type.
   This is useful when writing in imperative style, the simplest
   form of it is inserting a debug print. *)
let print_and_return x =
    print_endline (string_of_int x);
    x
;;

(* Since OCaml is a functional language, it lacks "procedures".
   Every function must return something. So functions that
   do not really return anything and are called solely for their
   side effects, like print_endline, return value of "unit" type. *)


(* Definitions can be chained with "let ... in" construct.
   This is roughly the same to assigning values to multiple
   variables before using them in expressions in imperative
   languages. *)
let x = 10 in
let y = 20 in
x + y ;;

(* Alternatively you can use "let ... and ... in" construct.
   This is especially useful for mutually recursive functions,
   with ordinary "let .. in" the compiler will complain about
   unbound values. *)
let rec
  is_even = function
  | 0 -> true
  | n -> is_odd (n-1)
and
  is_odd = function
  | 0 -> false
  | n -> is_even (n-1)
;;

(* Anonymous functions use the following syntax: *)
let my_lambda = fun x -> x * x ;;

(*** Operators ***)

(* There is little distinction between operators and functions.
   Every operator can be called as a function. *)

(+) 3 4  (* Same as 3 + 4 *)

(* There's a number of built-in operators. One unusual feature is
   that OCaml doesn't just refrain from any implicit conversions
   between integers and floats, it also uses different operators
   for floats. *)
12 + 3 ;; (* Integer addition. *)
12.0 +. 3.0 ;; (* Floating point addition. *)

12 / 3 ;; (* Integer division. *)
12.0 /. 3.0 ;; (* Floating point division. *)
5 mod 2 ;; (* Remainder. *)

(* Unary minus is a notable exception, it's polymorphic.
   However, it also has "pure" integer and float forms. *)
- 3 ;; (* Polymorphic, integer *)
- 4.5 ;; (* Polymorphic, float *)
~- 3 (* Integer only *)
~- 3.4 (* Type error *)
~-. 3.4 (* Float only *)

(* You can define your own operators or redefine existing ones.
   Unlike SML or Haskell, only selected symbols can be used
   for operator names and first symbol defines associativity
   and precedence rules. *)
let (+) a b = a - b ;; (* Surprise maintenance programmers. *)

(* More useful: a reciprocal operator for floats.
   Unary operators must start with "~". *)
let (~/) x = 1.0 /. x ;;
~/4.0 (* = 0.25 *)


(*** Built-in data structures ***)

(* Lists are enclosed in square brackets, items are separated by
   semicolons. *)
let my_list = [1; 2; 3] ;;

(* Tuples are (optionally) enclosed in parentheses, items are separated
   by commas. *)
let first_tuple = 3, 4 ;; (* Has type "int * int". *)
let second_tuple = (4, 5) ;;

(* Corollary: if you try to separate list items by commas, you get a list
   with a tuple inside, probably not what you want. *)
let bad_list = [1, 2] ;; (* Becomes [(1, 2)] *)

(* You can access individual list items with the List.nth function. *)
List.nth my_list 1 ;;

(* There are higher-order functions for lists such as map and filter. *)
List.map (fun x -> x * 2) [1; 2; 3] ;;
List.filter (fun x -> x mod 2 = 0) [1; 2; 3; 4] ;;

(* You can add an item to the beginning of a list with the "::" constructor
   often referred to as "cons". *)
1 :: [2; 3] ;; (* Gives [1; 2; 3] *)

(* Arrays are enclosed in [| |] *)
let my_array = [| 1; 2; 3 |] ;;

(* You can access array items like this: *)
my_array.(0) ;;


(*** Strings and characters ***)

(* Use double quotes for string literals. *)
let my_str = "Hello world" ;;

(* Use single quotes for character literals. *)
let my_char = 'a' ;;

(* Single and double quotes are not interchangeable. *)
let bad_str = 'syntax error' ;; (* Syntax error. *)

(* This will give you a single character string, not a character. *)
let single_char_str = "w" ;;

(* Strings can be concatenated with the "^" operator. *)
let some_str = "hello" ^ "world" ;;

(* Strings are not arrays of characters.
   You can't mix characters and strings in expressions.
   You can convert a character to a string with "String.make 1 my_char".
   There are more convenient functions for this purpose in additional
   libraries such as Core.Std that may not be installed and/or loaded
   by default. *)
let ocaml = (String.make 1 'O') ^ "Caml" ;;

(* There is a printf function. *)
Printf.printf "%d %s" 99 "bottles of beer" ;;

(* Unformatted read and write functions are there too. *)
print_string "hello world\n" ;;
print_endline "hello world" ;;
let line = read_line () ;;


(*** User-defined data types ***)

(* You can define types with the "type some_type =" construct. Like in this
   useless type alias: *)
type my_int = int ;;

(* More interesting types include so called type constructors.
   Constructors must start with a capital letter. *)
type ml = OCaml | StandardML ;;
let lang = OCaml ;;  (* Has type "ml". *)

(* Type constructors don't need to be empty. *)
type my_number = PlusInfinity | MinusInfinity | Real of float ;;
let r0 = Real (-3.4) ;; (* Has type "my_number". *)

(* Can be used to implement polymorphic arithmetics. *)
type number = Int of int | Float of float ;;

(* Point on a plane, essentially a type-constrained tuple *)
type point2d = Point of float * float ;;
let my_point = Point (2.0, 3.0) ;;

(* Types can be parameterized, like in this type for "list of lists
   of anything". 'a can be substituted with any type. *)
type 'a list_of_lists = 'a list list ;;
type int_list_list = int list_of_lists ;;

(* Types can also be recursive. Like in this type analogous to
   built-in list of integers. *)
type my_int_list = EmptyList | IntList of int * my_int_list ;;
let l = IntList (1, EmptyList) ;;


(*** Pattern matching ***)

(* Pattern matching is somewhat similar to switch statement in imperative
   languages, but offers a lot more expressive power.

   Even though it may look complicated, it really boils down to matching
   an argument against an exact value, a predicate, or a type constructor.
   The type system is what makes it so powerful. *)

(** Matching exact values.  **)

let is_zero x =
    match x with
    | 0 -> true
    | _ -> false  (* The "_" pattern means "anything else". *)
;;

(* Alternatively, you can use the "function" keyword. *)
let is_one = function
| 1 -> true
| _ -> false
;;

(* Matching predicates, aka "guarded pattern matching". *)
let abs x =
    match x with
    | x when x < 0 -> -x
    | _ -> x
;;

abs 5 ;; (* 5 *)
abs (-5) (* 5 again *)

(** Matching type constructors **)

type animal = Dog of string | Cat of string ;;

let say x =
    match x with
    | Dog x -> x ^ " says woof"
    | Cat x -> x ^ " says meow"
;;

say (Cat "Fluffy") ;; (* "Fluffy says meow". *)

(** Traversing data structures with pattern matching **)

(* Recursive types can be traversed with pattern matching easily.
   Let's see how we can traverse a data structure of the built-in list type.
   Even though the built-in cons ("::") looks like an infix operator,
   it's actually a type constructor and can be matched like any other. *)
let rec sum_list l =
    match l with
    | [] -> 0
    | head :: tail -> head + (sum_list tail)
;;

sum_list [1; 2; 3] ;; (* Evaluates to 6 *)

(* Built-in syntax for cons obscures the structure a bit, so we'll make
   our own list for demonstration. *)

type int_list = Nil | Cons of int * int_list ;;
let rec sum_int_list l =
  match l with
      | Nil -> 0
      | Cons (head, tail) -> head + (sum_int_list tail)
;;

let t = Cons (1, Cons (2, Cons (3, Nil))) ;;
sum_int_list t ;;

```

# sync.Once
# sync.Mutex
# sync.RWMutex
# sync.WaitGroup
# atomic 相关
# happens before