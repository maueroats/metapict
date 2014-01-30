#lang racket

(provide
 color         ; match-expander for color% objects and color names (strings)
 make-color*   ; fault tolerant make-color that also accepts color names
 color->list   ; return components as a list
 color+        ; add colors componentwise
 color*        ; scale componentwise
 color-med     ; mediate (interpolate) between colors
 change-red    ; change red component
 change-green  ; change green component
 change-blue   ; change blue component 
 change-alpha  ; change transparency
 )

(require "def.rkt" racket/draw (for-syntax syntax/parse) (only-in pict colorize))
(module+ test (require rackunit))

; (color r g b a) matches a color name (as a string) or a color% object.
; The variables r g b a will be bound to the red, gren, blue and alpha component respectively.

; In an expression context (color c p) will be equivalent to (colorize p c)
; In an expression context (color f c p) will be equivalent to (colorize p (color* f c))

(define-match-expander color
  (λ (stx) 
    (syntax-parse stx 
      [(_ r g b a)
       #'(or (and (? string?) 
                  (app (λ(s) (def c (send the-color-database find-color s))
                         (list (send c red) (send c green) (send c blue) (send c alpha)))
                       (list r g b a)))
             (and (? object?)
                  (app (λ(c) (list (send c red) (send c green) (send c blue) (send c alpha)))
                       (list r g b a))))]))
  (λ (stx) (syntax-parse stx 
             [(_ c p)   #'(colorize p c)]
             [(_ f c p) #'(colorize p (color* f c))])))

; return components as a list
(define (color->list c)
  (defm (color r g b α) c)
  (list r g b α))

; (make-color* s) where s is a color name returns the corresponding color% object
; (make-color r g b [α 1.0]) like make-color but accepts out-of-range numbers
(define make-color* 
  (case-lambda
    [(name) (let () 
              (def c (send the-color-database find-color name))
              (unless c (error 'make-color* (~a "expected color name, got ")))
              c)]
    [(r g b)   (make-color* r g b 1.0)]
    [(r g b α) (def (f x) (min 255 (max 0 (exact-floor x))))
               (make-color (f r) (f g) (f b) (max 0.0 (min 1.0 α)))]))

(module+ test
  (check-equal? (color->list (make-color* 1 2 3 .4)) '(1 2 3 .4))
  (check-equal? (color->list (make-color* "red")) '(255 0 0 1.)))

; add colors componentwise
(define (color+ color1 color2)  
  (defm (color r1 g1 b1 α1) color1)
  (defm (color r2 g2 b2 α2) color2)
  (make-color* (+ r1 r2) (+ g1 g2) (+ b1 b2) (min 1.0 (+ α1 α2))))

(module+ test
  (check-equal? (color->list (color+ "red" "blue")) '(255 0 255 1.))
  (check-equal? (color->list (color+ "red" (make-color* 0 0 0 2.))) '(255 0 0 1.)))

; multiply each color component with k, keep transparency
(define (color* k c)
  (defm (color r g b α) c)
  (make-color* (* k r) (* k g) (* k b) α))

(module+ test
  (check-equal? (color->list (color* 2 (make-color* 1 2 3 .4))) '(2 4 6 .4)))

; mediate (interpolate) between colors 0<=t<=1
(define (color-med t c1 c2)   
  (color+ (color* t c1) (color* (- 1 t) c2)))

(module+ test
  (check-equal? (color->list (color-med 1/2 "red" "blue")) '(127 0 127 1.)))

; change a single component 
(define (change-red   c r) (defm (color _ g b α) c) (make-color* r g b α))
(define (change-green c g) (defm (color r _ b α) c) (make-color* r g b α))
(define (change-blue  c b) (defm (color r g _ α) c) (make-color* r g b α))
(define (change-alpha c α) (defm (color r g b _) c) (make-color* r g b α))

(module+ test
  (check-equal? (color->list (change-red   "black"  7)) '(7 0 0 1.))
  (check-equal? (color->list (change-green "black"  7)) '(0 7 0 1.))
  (check-equal? (color->list (change-blue  "black"  7)) '(0 0 7 1.))
  (check-equal? (color->list (change-alpha "black" .7)) '(0 0 0 .7)))