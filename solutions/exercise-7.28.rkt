#lang eopl

;; Exercise 7.28 [★★] Our inferencer is very useful, but it is not powerful enough to allow the programmer to define
;; procedures that are polymorphic, like the polymorphic primitives pair or cons, which can be used at many types. For
;; example, our inferencer would reject the program
;;
;;     let f = proc (x : ?) x
;;     in if (f zero?(0))
;;        then (f 11)
;;        else (f 22)
;;
;; even though its execution is safe, because f is used both at type (bool -> bool) and at type (int -> int). Since the
;; inferencer of this section is allowed to find at most one type for f, it will reject this program.
;;
;; For a more realistic example, one would like to write programs like
;;
;;     letrec
;;      ? map (f : ?) =
;;         letrec
;;          ? foo (x : ?) = if null?(x)
;;                          then emptylist
;;                          else cons((f car(x)),
;;                                    ((map f) cdr(x)))
;;         in foo
;;     in letrec
;;         ? even (y : ?) = if zero?(y)
;;                          then zero?(0)
;;                          else if zero?(-(y,1))
;;                               then zero?(1)
;;                               else (even -(y,2))
;;        in pair(((map proc(x : int)-(x,1))
;;                cons(3,cons(5,emptylist))),
;;                ((map even)
;;                 cons(3,cons(5,emptylist))))
;;
;; This expression uses map twice, once producing a list of ints and once producing a list of bools. Therefore it needs
;; two different types for the two uses. Since the inferencer of this section will find at most one type for map, it
;; will detect the clash between int and bool and reject the program.
;;
;; One way to avoid this problem is to allow polymorphic values to be introduced only by let, and then to treat
;; (let-exp var e1 e2) differently from (call-exp (proc-exp var e2) e1) for type-checking purposes.
;;
;; Add polymorphic bindings to the inferencer by treating (let-exp var e1 e2) like the expression obtained by
;; substituting e1 for each free occurrence of var in e2. Then, from the point of view of the inferencer, there are many
;; different copies of e1 in the body of the let, so they can have different types, and the programs above will be
;; accepted.

;; Grammar.

(define the-lexical-spec
  '([whitespace (whitespace) skip]
    [comment ("%" (arbno (not #\newline))) skip]
    [identifier (letter (arbno (or letter digit "_" "-" "?"))) symbol]
    [number (digit (arbno digit)) number]
    [number ("-" digit (arbno digit)) number]))

(define the-grammar
  '([program (expression) a-program]
    [expression (number) const-exp]
    [expression ("-" "(" expression "," expression ")") diff-exp]
    [expression ("zero?" "(" expression ")") zero?-exp]
    [expression ("if" expression "then" expression "else" expression) if-exp]
    [expression (identifier) var-exp]
    [expression ("let" identifier "=" expression "in" expression) let-exp]
    [expression ("proc" "(" identifier ":" optional-type ")" expression) proc-exp]
    [expression ("(" expression expression ")") call-exp]
    [expression ("letrec" optional-type identifier "(" identifier ":" optional-type ")" "=" expression "in" expression)
                letrec-exp]
    [expression ("pair" "(" expression "," expression ")") pair-exp]
    [expression ("unpair" identifier identifier "=" expression "in" expression) unpair-exp]
    [expression ("list" "(" expression (arbno "," expression) ")") list-exp]
    [expression ("cons" "(" expression "," expression ")") cons-exp]
    [expression ("null?" "(" expression ")") null-exp]
    [expression ("emptylist") emptylist-exp]
    [expression ("car" "(" expression ")") car-exp]
    [expression ("cdr" "(" expression ")") cdr-exp]
    [optional-type ("?") no-type]
    [optional-type (type) a-type]
    [type ("int") int-type]
    [type ("bool") bool-type]
    [type ("(" type "->" type ")") proc-type]
    [type ("pairof" type "*" type) pair-type]
    [type ("listof" type) list-type]
    [type ("%tvar-type" number) tvar-type]))

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define scan&parse (sllgen:make-string-parser the-lexical-spec the-grammar))

(define proc-type?
  (lambda (ty)
    (cases type ty
      [proc-type (t1 t2) #t]
      [else #f])))

(define pair-type?
  (lambda (ty)
    (cases type ty
      [pair-type (t1 t2) #t]
      [else #f])))

(define list-type?
  (lambda (ty)
    (cases type ty
      [list-type (t1) #t]
      [else #f])))

(define tvar-type?
  (lambda (ty)
    (cases type ty
      [tvar-type (serial-number) #t]
      [else #f])))

(define proc-type->arg-type
  (lambda (ty)
    (cases type ty
      [proc-type (arg-type result-type) arg-type]
      [else (eopl:error 'proc-type->arg-type "Not a proc type: ~s" ty)])))

(define proc-type->result-type
  (lambda (ty)
    (cases type ty
      [proc-type (arg-type result-type) result-type]
      [else (eopl:error 'proc-type->result-types "Not a proc type: ~s" ty)])))

(define pair-type->first-type
  (lambda (ty)
    (cases type ty
      [pair-type (ty1 ty2) ty1]
      [else (eopl:error 'pair-type->first-type "Not a pair type: ~s" ty)])))

(define pair-type->second-type
  (lambda (ty)
    (cases type ty
      [pair-type (ty1 ty2) ty2]
      [else (eopl:error 'pair-type->second-type "Not a pair type: ~s" ty)])))

(define list-type->item-type
  (lambda (ty)
    (cases type ty
      [list-type (ty1) ty1]
      [else (eopl:error 'list-type->item-type "Not a list type: ~s" ty)])))

(define type-to-external-form
  (lambda (ty)
    (cases type ty
      [int-type () 'int]
      [bool-type () 'bool]
      [proc-type (arg-type result-type) (list (type-to-external-form arg-type) '-> (type-to-external-form result-type))]
      [pair-type (ty1 ty2) (list 'pairof (type-to-external-form ty1) '* (type-to-external-form ty2))]
      [list-type (ty) (list 'listof (type-to-external-form ty))]
      [tvar-type (serial-number) (string->symbol (string-append "tvar" (number->string serial-number)))])))

;; Data structures - expressed values.

(define-datatype proc proc?
  [procedure [bvar symbol?]
             [body expression?]
             [env environment?]])

(define-datatype expval expval?
  [num-val [value number?]]
  [bool-val [boolean boolean?]]
  [proc-val [proc proc?]]
  [pair-val [val1 expval?]
            [val2 expval?]]
  [emptylist-val]
  [list-val [head expval?]
            [tail expval?]])

(define expval-extractor-error
  (lambda (variant value)
    (eopl:error 'expval-extractors "Looking for a ~s, found ~s" variant value)))

(define expval->num
  (lambda (v)
    (cases expval v
      [num-val (num) num]
      [else (expval-extractor-error 'num v)])))

(define expval->bool
  (lambda (v)
    (cases expval v
      [bool-val (bool) bool]
      [else (expval-extractor-error 'bool v)])))

(define expval->proc
  (lambda (v)
    (cases expval v
      [proc-val (proc) proc]
      [else (expval-extractor-error 'proc v)])))

(define expval->pair
  (lambda (v f)
    (cases expval v
      [pair-val (val1 val2) (f val1 val2)]
      [else (expval-extractor-error 'pair v)])))

(define expval->list
  (lambda (v f)
    (cases expval v
      [list-val (head tail) (f head tail)]
      [else (expval-extractor-error 'list v)])))

;; Data structures - environment.

(define-datatype environment environment?
  [empty-env]
  [extend-env [bvar symbol?]
              [bval expval?]
              [saved-env environment?]]
  [extend-env-rec [p-name symbol?]
                  [b-var symbol?]
                  [p-body expression?]
                  [saved-env environment?]])

(define apply-env
  (lambda (env search-sym)
    (cases environment env
      [empty-env () (eopl:error 'apply-env "No binding for ~s" search-sym)]
      [extend-env (bvar bval saved-env) (if (eqv? search-sym bvar)
                                            bval
                                            (apply-env saved-env search-sym))]
      [extend-env-rec (p-name b-var p-body saved-env) (if (eqv? search-sym p-name)
                                                          (proc-val (procedure b-var p-body env))
                                                          (apply-env saved-env search-sym))])))

;; Data structures - type environment.

(define-datatype type-environment type-environment?
  [empty-tenv-record]
  [extended-tenv-record [sym symbol?]
                        [type type?]
                        [tenv type-environment?]]
  [extended-tenv-delayed-record [sym symbol?]
                                [f procedure?]
                                [tenv type-environment?]])

(define empty-tenv empty-tenv-record)
(define extend-tenv extended-tenv-record)
(define extend-tenv-delayed extended-tenv-delayed-record)

(define apply-tenv
  (lambda (tenv sym)
    (cases type-environment tenv
      [empty-tenv-record () (eopl:error 'apply-tenv "Unbound variable ~s" sym)]
      [extended-tenv-record (sym1 val1 old-env) (if (eqv? sym sym1)
                                                    val1
                                                    (apply-tenv old-env sym))]
      [extended-tenv-delayed-record (sym1 f old-env) (if (eqv? sym sym1)
                                                         f
                                                         (apply-tenv old-env sym))])))

;; Data structures - substitution.

(define pair-of
  (lambda (pred1 pred2)
    (lambda (val)
      (and (pair? val) (pred1 (car val)) (pred2 (cdr val))))))

(define substitution?
  (list-of (pair-of tvar-type? type?)))

(define empty-subst
  (lambda ()
    '()))

(define apply-one-subst
  (lambda (ty0 tvar ty1)
    (cases type ty0
      [int-type () (int-type)]
      [bool-type () (bool-type)]
      [proc-type (arg-type result-type) (proc-type (apply-one-subst arg-type tvar ty1)
                                                   (apply-one-subst result-type tvar ty1))]
      [pair-type (left-ty right-ty) (pair-type (apply-one-subst tvar left-ty) (apply-one-subst tvar right-ty))]
      [list-type (ty) (list-type (apply-one-subst ty tvar ty1))]
      [tvar-type (sn) (if (equal? ty0 tvar) ty1 ty0)])))

(define extend-subst
  (lambda (subst tvar ty)
    (cons (cons tvar ty)
          (map (lambda (p)
                 (let ([oldlhs (car p)]
                       [oldrhs (cdr p)])
                   (cons oldlhs (apply-one-subst oldrhs tvar ty))))
               subst))))

(define apply-subst-to-type
  (lambda (ty subst)
    (cases type ty
      [int-type () (int-type)]
      [bool-type () (bool-type)]
      [proc-type (t1 t2) (proc-type (apply-subst-to-type t1 subst) (apply-subst-to-type t2 subst))]
      [pair-type (left-ty right-ty) (pair-type (apply-subst-to-type left-ty subst)
                                               (apply-subst-to-type right-ty subst))]
      [list-type (ty1) (list-type (apply-subst-to-type ty1 subst))]
      [tvar-type (sn) (let ([tmp (assoc ty subst)])
                        (if tmp
                            (cdr tmp)
                            ty))])))

;; Data structures - answer.

(define-datatype answer answer?
  [an-answer [type type?]
             [subst substitution?]])

;; Unifier.

(define no-occurrence?
  (lambda (tvar ty)
    (cases type ty
      [int-type () #t]
      [bool-type () #t]
      [proc-type (arg-type result-type) (and (no-occurrence? tvar arg-type)
                                             (no-occurrence? tvar result-type))]
      [pair-type (left-ty right-ty) (and (no-occurrence? tvar left-ty)
                                         (no-occurrence? tvar right-ty))]
      [list-type (ty1) (no-occurrence? tvar ty1)]
      [tvar-type (serial-number) (not (equal? tvar ty))])))

(define report-no-occurrence-violation
  (lambda (ty1 ty2 exp)
    (eopl:error 'check-no-occurence!
                "Can't unify: type variable ~s occurs in type ~s in expression ~s~%"
                (type-to-external-form ty1)
                (type-to-external-form ty2)
                exp)))

(define report-unification-failure
  (lambda (ty1 ty2 exp)
    (eopl:error 'unification-failure
                "Type mismatch: ~s doesn't match ~s in ~s~%"
                (type-to-external-form ty1)
                (type-to-external-form ty2)
                exp)))

(define unifier
  (lambda (ty1 ty2 subst exp)
    (let ([ty1 (apply-subst-to-type ty1 subst)]
          [ty2 (apply-subst-to-type ty2 subst)])
      (cond [(equal? ty1 ty2) subst]
            [(tvar-type? ty1) (if (no-occurrence? ty1 ty2)
                                  (extend-subst subst ty1 ty2)
                                  (report-no-occurrence-violation ty1 ty2 exp))]
            [(tvar-type? ty2) (if (no-occurrence? ty2 ty1)
                                  (extend-subst subst ty2 ty1)
                                  (report-no-occurrence-violation ty2 ty1 exp))]
            [(and (proc-type? ty1) (proc-type? ty2)) (let ([subst (unifier (proc-type->arg-type ty1)
                                                                           (proc-type->arg-type ty2)
                                                                           subst
                                                                           exp)])
                                                       (let ([subst (unifier (proc-type->result-type ty1)
                                                                             (proc-type->result-type ty2)
                                                                             subst
                                                                             exp)])
                                                         subst))]
            [(and (pair-type? ty1) (pair-type? ty2)) (let ([subst (unifier (pair-type->first-type ty1)
                                                                           (pair-type->first-type ty2)
                                                                           subst
                                                                           exp)])
                                                       (let ([subst (unifier (pair-type->second-type ty1)
                                                                             (pair-type->second-type ty2)
                                                                             subst
                                                                             exp)])
                                                         subst))]
            [(and (list-type? ty1) (list-type? ty2)) (unifier (list-type->item-type ty1)
                                                              (list-type->item-type ty2)
                                                              subst
                                                              exp)]
            [else (report-unification-failure ty1 ty2 exp)]))))

;; Inferrer.

(define sn 'uninitialized)

(define fresh-tvar-type
  (let ([sn 0])
    (lambda ()
      (set! sn (+ sn 1))
      (tvar-type sn))))

(define otype->type
  (lambda (otype)
    (cases optional-type otype
      [no-type () (fresh-tvar-type)]
      [a-type (ty) ty])))

(define type-of
  (lambda (exp tenv subst)
    (cases expression exp
      [const-exp (num) (an-answer (int-type) subst)]
      [zero?-exp (exp1) (cases answer (type-of exp1 tenv subst)
                          [an-answer (type1 subst1) (let ([subst2 (unifier type1 (int-type) subst1 exp)])
                                                      (an-answer (bool-type) subst2))])]
      [diff-exp (exp1 exp2) (cases answer (type-of exp1 tenv subst)
                              [an-answer (type1 subst1) (let ([subst1 (unifier type1 (int-type) subst1 exp1)])
                                                          (cases answer (type-of exp2 tenv subst1)
                                                            [an-answer (type2 subst2) (let ([subst2 (unifier type2
                                                                                                             (int-type)
                                                                                                             subst2
                                                                                                             exp2)])
                                                                                        (an-answer (int-type)
                                                                                                   subst2))]))])]
      [if-exp (exp1 exp2 exp3)
              (cases answer (type-of exp1 tenv subst)
                [an-answer (ty1 subst) (let ([subst (unifier ty1 (bool-type) subst exp1)])
                                         (cases answer (type-of exp2 tenv subst)
                                           [an-answer (ty2 subst) (cases answer (type-of exp3 tenv subst)
                                                                    [an-answer (ty3 subst) (let ([subst (unifier ty2
                                                                                                                 ty3
                                                                                                                 subst
                                                                                                                 exp)])
                                                                                             (an-answer ty2
                                                                                                        subst))])]))])]
      [var-exp (var) (let ([var-type (apply-tenv tenv var)])
                       (if (type? var-type)
                           (an-answer var-type subst)
                           (var-type subst)))]
      [let-exp (var exp1 body)
               (type-of exp1 tenv subst) ;; Make sure exp1 is checked.
               (type-of body
                        (extend-tenv-delayed var
                                             (lambda (subst)
                                               (type-of exp1 tenv subst))
                                             tenv)
                        subst)]
      [proc-exp (var otype body) (let ([arg-type (otype->type otype)])
                                   (cases answer (type-of body (extend-tenv var arg-type tenv) subst)
                                     [an-answer (result-type subst)
                                                (an-answer (proc-type arg-type result-type) subst)]))]
      [call-exp (rator rand)
                (let ([result-type (fresh-tvar-type)])
                  (cases answer (type-of rator tenv subst)
                    [an-answer (rator-type subst)
                               (cases answer (type-of rand tenv subst)
                                 [an-answer (rand-type subst) (let ([subst (unifier rator-type
                                                                                    (proc-type rand-type result-type)
                                                                                    subst
                                                                                    exp)])
                                                                (an-answer result-type subst))])]))]
      [letrec-exp (proc-result-otype proc-name bvar proc-arg-otype proc-body letrec-body)
                  (define check-proc
                    (lambda (subst)
                      (let* ([proc-result-type (otype->type proc-result-otype)]
                             [proc-arg-type (otype->type proc-arg-otype)]
                             [proc-type1 (proc-type proc-arg-type proc-result-type)])
                        (cases answer (type-of proc-body
                                               (extend-tenv bvar
                                                            proc-arg-type
                                                            (extend-tenv proc-name
                                                                         proc-type1
                                                                         tenv))
                                               subst)
                          [an-answer (proc-body-type subst)
                                     (let ([subst (unifier proc-body-type
                                                           proc-result-type
                                                           subst
                                                           proc-body)])
                                       (an-answer proc-type1 subst))]))))
                  (check-proc subst) ;; Make sure proc-body is checked.
                  (type-of letrec-body
                           (extend-tenv-delayed proc-name
                                                check-proc
                                                tenv)
                           subst)]
      [pair-exp (exp1 exp2) (cases answer (type-of exp1 tenv subst)
                              [an-answer (ty1 subst) (cases answer (type-of exp2 tenv subst)
                                                       [an-answer (ty2 subst) (an-answer (pair-type ty1 ty2) subst)])])]
      [unpair-exp (var1 var2 exp1 body)
                  (cases answer (type-of exp1 tenv subst)
                    [an-answer (exp-ty subst) (let ([ty1 (fresh-tvar-type)]
                                                    [ty2 (fresh-tvar-type)])
                                                (type-of body
                                                         (extend-tenv var2
                                                                      ty2
                                                                      (extend-tenv var1 ty1 tenv))
                                                         (unifier (pair-type ty1 ty2) exp-ty subst exp1)))])]
      [list-exp (exp1 exps) (cases answer (type-of exp1 tenv subst)
                              [an-answer (ty1 subst) (let loop ([subst subst]
                                                                [exps exps])
                                                       (if (null? exps)
                                                           (an-answer (list-type ty1) subst)
                                                           (let ([exp2 (car exps)])
                                                             (cases answer (type-of exp2 tenv subst)
                                                               [an-answer (ty2 subst) (loop (unifier ty1 ty2 subst exp2)
                                                                                            (cdr exps))]))))])]
      [cons-exp (exp1 exp2) (cases answer (type-of exp1 tenv subst)
                              [an-answer (ty1 subst) (cases answer (type-of exp2 tenv subst)
                                                       [an-answer (ty2 subst) (an-answer ty2
                                                                                         (unifier (list-type ty1)
                                                                                                  ty2
                                                                                                  subst
                                                                                                  exp2))])])]
      [null-exp (exp1) (cases answer (type-of exp1 tenv subst)
                         [an-answer (ty1 subst) (an-answer (bool-type)
                                                           (unifier (list-type (fresh-tvar-type)) ty1 subst exp1))])]
      [emptylist-exp () (an-answer (list-type (fresh-tvar-type)) subst)]
      [car-exp (exp1) (cases answer (type-of exp1 tenv subst)
                        [an-answer (ty1 subst) (let ([ty2 (fresh-tvar-type)])
                                                 (an-answer ty2 (unifier ty1 (list-type ty2) subst exp1)))])]
      [cdr-exp (exp1) (cases answer (type-of exp1 tenv subst)
                        [an-answer (ty1 subst) (let ([ty2 (fresh-tvar-type)])
                                                 (an-answer ty1 (unifier ty1 (list-type ty2) subst exp1)))])])))

(define type-of-program
  (lambda (pgm)
    (cases program pgm
      [a-program (exp1) (cases answer (type-of exp1 (empty-tenv) (empty-subst))
                          [an-answer (ty subst) (apply-subst-to-type ty subst)])])))

;; Interpreter.

(define apply-procedure
  (lambda (proc1 arg)
    (cases proc proc1
      [procedure (var body saved-env) (value-of body (extend-env var arg saved-env))])))

(define value-of
  (lambda (exp env)
    (cases expression exp
      [const-exp (num) (num-val num)]
      [var-exp (var) (apply-env env var)]
      [diff-exp (exp1 exp2) (let ([val1 (expval->num (value-of exp1 env))]
                                  [val2 (expval->num (value-of exp2 env))])
                              (num-val (- val1 val2)))]
      [zero?-exp (exp1) (let ([val1 (expval->num (value-of exp1 env))])
                          (if (zero? val1)
                              (bool-val #t)
                              (bool-val #f)))]
      [if-exp (exp0 exp1 exp2) (if (expval->bool (value-of exp0 env))
                                   (value-of exp1 env)
                                   (value-of exp2 env))]
      [let-exp (var exp1 body) (let ([val (value-of exp1 env)])
                                 (value-of body (extend-env var val env)))]
      [proc-exp (bvar ty body) (proc-val (procedure bvar body env))]
      [call-exp (rator rand) (let ([proc (expval->proc (value-of rator env))]
                                   [arg (value-of rand env)])
                               (apply-procedure proc arg))]
      [letrec-exp (ty1 p-name b-var ty2 p-body letrec-body) (value-of letrec-body
                                                                      (extend-env-rec p-name b-var p-body env))]
      [pair-exp (exp1 exp2) (pair-val (value-of exp1 env) (value-of exp2 env))]
      [unpair-exp (var1 var2 exp1 body) (let ([val (value-of exp1 env)])
                                          (expval->pair val
                                                        (lambda (val1 val2)
                                                          (value-of body (extend-env var2
                                                                                     val2
                                                                                     (extend-env var1 val1 env))))))]
      [list-exp (exp1 exps) (let loop1 ([acc '()]
                                        [exp1 exp1]
                                        [exps exps])
                              (if (null? exps)
                                  (let loop2 ([acc-list (list-val (value-of exp1 env) (emptylist-val))]
                                              [vals acc])
                                    (if (null? vals)
                                        acc-list
                                        (loop2 (list-val (car vals) acc-list)
                                               (cdr vals))))
                                  (loop1 (cons (value-of exp1 env) acc)
                                         (car exps)
                                         (cdr exps))))]
      [cons-exp (exp1 exp2) (list-val (value-of exp1 env)
                                      (value-of exp2 env))]
      [null-exp (exp1) (cases expval (value-of exp1 env)
                         [emptylist-val () (bool-val #t)]
                         [else (bool-val #f)])]
      [emptylist-exp () (emptylist-val)]
      [car-exp (exp1) (expval->list (value-of exp1 env)
                                    (lambda (head tail)
                                      head))]
      [cdr-exp (exp1) (expval->list (value-of exp1 env)
                                    (lambda (head tail)
                                      tail))])))

(define value-of-program
  (lambda (pgm)
    (cases program pgm
      [a-program (body) (value-of body (empty-env))])))

;; Interface.

(define check
  (lambda (string)
    (type-to-external-form (type-of-program (scan&parse string)))))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

(provide bool-val check emptylist-val list-val num-val run)
