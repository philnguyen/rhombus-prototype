#lang racket/base
(require (for-syntax racket/base
                     syntax/parse/pre
                     enforest/syntax-local
                     enforest/hier-name-parse
                     "name-path-op.rkt")
         "definition.rkt"
         (submod "annotation.rkt" for-class)
         "parens.rkt"
         "name-root-space.rkt"
         "name-root-ref.rkt"
         "dotted-sequence-parse.rkt"
         "static-info.rkt"
         "indirect-static-info-key.rkt")

(provide delayed_declare
         delayed_complete)

(begin-for-syntax
  (struct delayed-annotation annotation-prefix-operator (complete!-id
                                                         static-info-id
                                                         [completed? #:mutable]))
  (define (make-delayed-annotation proc complete!-id static-info-id)
    (delayed-annotation
     (quote-syntax ignored)
     '((default . stronger))
     'macro
     proc
     complete!-id
     static-info-id
     #f))
  (define (delayed-annotation-ref v) (and (delayed-annotation? v) v)))

(define (too-early who)
  (raise-arguments-error who "delayed annoation is not yet completed"))

(define-syntax delayed_declare
  (definition-transformer
    (lambda (stx)
      (syntax-parse stx
        [(_ name:id)
         #`((begin
              (define delayed-predicate (lambda (v) (too-early 'name)))
              (define (set-delayed-predicate! proc) (set! delayed-predicate proc))
              (define-syntax delayed-static-info (static-info
                                                  (let ([static-infos null])
                                                    (case-lambda
                                                      [() static-infos]
                                                      [(si) (set! static-infos si)]))))
              (define-syntax #,(in-annotation-space #'name)
                (letrec ([self (make-delayed-annotation
                                (lambda (stx)
                                  (values #`(delayed-predicate
                                             ((#%indirect-static-info delayed-static-info)))
                                          (syntax-parse stx
                                            [(_ . tail) #'tail]
                                            [_ 'does-not-happen])))
                                #'set-delayed-predicate!
                                #'delayed-static-info)])
                  self))))]))))

(define-syntax delayed_complete
  (definition-transformer
    (lambda (stx)
      (syntax-parse stx
        [(_ name-seq::dotted-identifier-sequence (_::block g))
         #:with (~var name (:hier-name-seq in-name-root-space in-annotation-space name-path-op name-root-ref)) #'name-seq
         #:do [(unless (null? (syntax-e #'name.tail))
                 (raise-syntax-error #f
                                     "not a delayed annotation name"
                                     stx
                                     #'name-seq))]
         #:with ap::annotation #'g
         #:with a::annotation-form #'ap.parsed
         (define dp (syntax-local-value* (in-annotation-space #'name.name) delayed-annotation-ref))
         (unless dp
           (raise-syntax-error #f
                               "not defined as a delayed annotation"
                               stx
                               #'name.name))
         #`((define-syntaxes ()
              (delayed-annotation-complete-compiletime #'name.name #'a.static-infos))
            (#,(delayed-annotation-complete!-id dp) a.predicate))]))))

(define-for-syntax (delayed-annotation-complete-compiletime name static-infos)
  (define dp (syntax-local-value* (in-annotation-space name) delayed-annotation-ref))
  (unless dp
    ;; should not happen:
    (raise-syntax-error #f "not a delayed annotation" name))
  (when (delayed-annotation-completed? dp)
    (raise-syntax-error #f
                        "delayed annotation is already completed"
                        name))
  (define si (syntax-local-value* (delayed-annotation-static-info-id dp) static-info-ref))
  (unless si
    ;; should not happen:
    (raise-syntax-error #f "static info not found" name))
  ((static-info-get-stxs si) static-infos)
  (set-delayed-annotation-completed?! dp #t)
  (values))