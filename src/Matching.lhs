\section{Matching}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module Matching ( match
                , tMatch, tsMatch
                , vMatch, bvMatch, kvMatch
                ) where
import Data.Maybe (isJust,fromJust)
import Data.Map (Map)
import qualified Data.Map as M
import Data.Set (Set)
import qualified Data.Set as S
import Control.Monad

--import Utilities
import LexBase
import AST
import VarData
import Binding
\end{code}

\subsection{Matching Principles}

We want to match a candidate term ($C$) against a pattern term ($P$)
in some context ($\Gamma$),
to obtain a binding ($\beta$), if successful,
of pattern variables to appropriate term components.
$$
\Gamma \vdash C :: P  \leadsto \beta
$$
The context has two components,
the first ($\kappa$) being the known variables,
and the second ($B$) keeping track of bound variables.
We need to track bound variables for both
the candidate ($B_C$)
and pattern ($B_P$)
$$
\kappa;(B_C,B_P) \vdash C :: P  \leadsto \beta
$$
The use-case that is most common in the planned use for matching
is where we want to match a single candidate against many patterns.
We expect most such matches to fail,
and so we want to design our algorithms
to discover failure as fast as possible.
This means doing top-level structural matching first,
and only then trying the more complex and tricky matching
of variable lists and sets.

The idea is that we attempt to construct a binding on-the-fly,
doing matching on one sub-component at a time,
passing the partial binding result along and attempting to add new bindings
directly into it.
$$
\kappa;\beta;(B_C,B_P) \vdash C :: P \leadsto \beta'
$$
We also posit a binary partial operator ($\uplus$) that merges two bindings
as long as overlapping entries agree,
so the assertion $\beta = \beta_1 \uplus \beta_2$ is true only if all overlapping entries in the $\beta_i$ agree,
and $\beta$ corresponds to their union.

We are not normally interested in the reason why a match fails,
so will generally use the \texttt{Maybe} type constructor.
However we code for a general monad with meaningful \texttt{fail} messages
to make it easier to debug or test.
We also need to support the idea that some patterns may match a given
candidate in more than one way,
so we would like to return a list of bindings,
leading us to adopt the \texttt{MonadPlus} class.
$$
\kappa;\beta;(B_C,B_P) \vdash C :: P
\leadsto \langle \beta'_1 , \dots , \beta'_n \rangle
$$
Each of the $\beta'_i$
has the general form $\beta'_{i1} \uplus \dots \uplus \beta'_{ik_i}$,
and a rule applies provided at least one of the $\beta'_i$ is defined.
We write $\langle\beta\rangle$ as $\beta$
and in most rules we omit irrelevant parts of the context.
\newpage
\subsection{Matching Types}

We introduce some type and value synonyms,
to make type-signatures more informative.
\begin{code}
type Pattern = Term
type Candidate = Term
type BVS = Set GenVar
type PBVS = BVS
type CBVS = BVS

noBVS = S.empty
\end{code}

We will want to add in sets and lists of variables
into the bound-variable sets.
\begin{code}
addBoundVarSet :: VarSet -> BVS -> BVS
vs `addBoundVarSet` bvs  =  vs `S.union` bvs

addBoundVarList :: VarList -> BVS -> BVS
vl `addBoundVarList` bvs  =  (S.fromList vl) `S.union` bvs
\end{code}

\subsection{Top-level Matching}

At the top-level we have the known-variable information
in the form of a sequence $\kappa s$ of known variable tables,
and the pattern and candidate terms,
and we hope to get at least one binding.
We initialise the bound-variable sets to empty ($\emptyset$)
and the bindings already obtained to the null map ($\theta$).
$$
\inferrule
   {\kappa s;\theta;(\emptyset,\emptyset) \vdash C :: P \leadsto \beta s}
   {\kappa s \vdash C :: P \leadsto \beta s}
   \quad
   \texttt{match}
$$
\begin{code}
match :: MonadPlus mp => [VarTable] -> Candidate -> Pattern -> mp Binding
match vts c p = tMatch vts emptyBinding noBVS noBVS c p
\end{code}

\subsection{Term Matching}

Term-matching is defined inductively over the pattern type.
\begin{code}
tMatch :: MonadPlus mp
       => [VarTable] -> Binding -> CBVS -> PBVS
       -> Candidate -> Pattern -> mp Binding
\end{code}
We start with the simple value and structural composite matches,
and then proceed to look at variable, binder and substitution patterns.

\subsubsection{Value Term-Pattern (\texttt{Val})}
Values only match themselves.
$$
\inferrule
   {{\kk k}_C = {\kk k}_P}
   {\beta \vdash {\kk k}_C :: {\kk k}_P \leadsto \beta}
   \quad
   \texttt{tMatch Val}
$$
\begin{code}
tMatch _ bind _ _ kC@(Val _ _) kP@(Val _ _)
 | kC == kP  =  return bind
\end{code}

\subsubsection{Variable Term-Pattern (\texttt{Var})}
Variable matching is complicated, so we farm it out,
as long as \texttt{TermKind}s match.
$$
\inferrule
   {\beta \vdash t_C :: v_P \leadsto \beta'}
   {\beta \vdash t_C :: {\vv v}_P \leadsto \beta'}
   \quad
   \texttt{tMatch Var}
$$
\begin{code}
tMatch vts bind cbvs pbvs tC (Var tkP vP)
  | tkP == termkind tC  =  vMatch vts bind cbvs pbvs tC tkP vP
\end{code}


\subsubsection{Constructor Term-Pattern (\texttt{Cons})}
Constructors match if they have the same name and kind
and the term-lists are of the same length and corresponding terms match.
$$
\inferrule
   { n_C = n_P
     \and
     \beta \vdash t_{C_i} :: t_{P_i} \leadsto \beta_i
   }
   {\beta \vdash \cc{n_C}{ts_C} :: \cc{n_P}{ts_P} \leadsto \uplus\{\beta_i\}}
   \quad
   \texttt{tMatch Cons}
$$
Here $ts_X = \langle t_{X_1}, t_{X_2}, \dots t_{X_n} \rangle$.
\begin{code}
tMatch vts bind cbvs pbvs (Cons tkC nC tsC) (Cons tkP nP tsP)
 | tkC == tkP && nC == nP  =  tsMatch vts bind cbvs pbvs tsC tsP
\end{code}

\subsubsection{Binding Term-Pattern (\texttt{Bind})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta;(B_C\cup vs_C,B_P\cup vs_P) \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash vs_C :: vs_P \leadsto \beta'_{vs}
   }
   { \beta;(B_C,B_P) \vdash \bb{n_C}{vs_C}{t_C} :: \bb{n_P}{vs_P}{t_P}
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_{vs}
   }
   \quad
   \texttt{tMatch Binding}
$$
\begin{code}
tMatch vts bind cbvs pbvs (Bind tkC nC vsC tC) (Bind tkP nP vsP tP)
  | tkP == tkC && nC == nP
    =  do let cbvs' = vsC `addBoundVarSet` cbvs
          let pbvs' = vsP `addBoundVarSet` pbvs
          bindT  <-  tMatch vts bind cbvs' pbvs' tC tP
          vsMatch vts bindT cbvs' pbvs' vsC vsP
\end{code}

\subsubsection{Lambda Term-Pattern (\texttt{Lam})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta;(B_C\cup vs_C,B_P\cup vs_P) \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash vl_C :: vl_P \leadsto \beta'_{vl}
   }
   { \beta;(B_C,B_P) \vdash \ll{n_C}{vl_C}{t_C} :: \ll{n_P}{vl_P}{t_P}
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_{vl}
   }
   \quad
   \texttt{tMatch Binding}
$$
\begin{code}
tMatch vts bind cbvs pbvs (Lam tkC nC vlC tC) (Lam tkP nP vlP tP)
  | tkP == tkC && nC == nP
    =  do let cbvs' = vlC `addBoundVarList` cbvs
          let pbvs' = vlP `addBoundVarList` pbvs
          bindT  <-  tMatch vts bind cbvs' pbvs' tC tP
          vlMatch vts bindT cbvs' pbvs' vlC vlP
\end{code}


\subsubsection{Substitution Term-Pattern (\texttt{Sub})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash \sigma_C :: \sigma_P \leadsto \beta'_\sigma
   }
   { \beta \vdash t_C\sigma_C :: t_P\sigma_P
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_\sigma
   }
   \quad
   \texttt{tMatch Subst}
$$
\begin{code}
tMatch vts bind cbvs pbvs (Sub tkC tC subC) (Sub tkP tP subP)
  | tkP == tkC
    =  do bindT  <-  tMatch vts bind cbvs pbvs tC tP
          sMatch vts bindT cbvs pbvs subC subP
\end{code}


\subsubsection{Iterated Term-Pattern (\texttt{Iter})}

$$
\inferrule
   {na_C = na_P \land ni_C = ni_P
    \and
    \beta \vdash lvs_C :: lvs_P \leadsto \beta'
   }
   { \beta \vdash \ii{na_C}{ni_C}{lvs_C} :: \ii{na_P}{ni_P}{lvs_P}
     \leadsto
     \beta \uplus \beta\
   }
   \quad
   \texttt{tMatch Iter}
$$
Plus a more complicated rule !
\begin{code}
tMatch vts bind cbvs pbvs (Iter tkC naC niC lvsC) (Iter tkP naP niP lvsP)
  | tkP == tkC && naC == naP && niC == niP
    =  fail "tMatch Iter :: Iter N.Y.I."
tMatch vts bind cbvs pbvs tC (Iter tkP naP niP lvsP)
  | tkP == termkind tC
    =  fail "tMatch non-Iter :: Iter N.Y.I."
\end{code}

Any other case results in failure:
\begin{code}
tMatch _ _ _ _ _ _  =  fail "tMatch: structural mismatch."
\end{code}

\subsection{Term-List Matching}

For now a simple zip-like walk along both lists
(no precomputing length to abort early).
\begin{code}
tsMatch :: MonadPlus mp
        => [VarTable] -> Binding -> CBVS -> PBVS
        -> [Candidate] -> [Pattern] -> mp Binding
tsMatch _ bind _ _ [] [] = return bind
tsMatch vts bind cbvs pvbs (tC:tsC) (tP:tsP)
 = do bind1 <- tMatch vts bind cbvs pvbs tC tP
      tsMatch vts bind1 cbvs pvbs tsC tsP
tsMatch _ _ _ _ _ _  =  fail "tsMatch: structural mismatch."
\end{code}

\newpage
\subsection{Variable Matching}

We assume here that candidate term and pattern variable
had the same \texttt{TermKind}.
\begin{code}
vMatch :: Monad m
       => [VarTable] -> Binding -> CBVS -> PBVS
       -> Candidate -> TermKind -> Variable -> m Binding
\end{code}
We do a case split on the status of the pattern variable:
bound, known, or arbitrary.
\begin{code}
vMatch vts bind cbvs pvbs tC tkP vP
 | StdVar vP `S.member` pvbs  =  bvMatch vts bind cbvs tC vP
 | vPmr /= UnknownVar         =  kvMatch vts bind tC vPmr tkP vP
\end{code}
\subsubsection{Arbitrary Pattern Variable}
$$
\inferrule
   { v_P \notin B_P \cup \mathbf{dom}\,\kappa s}
   { \kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}
  }
   \quad
   \texttt{vMatch Arbitrary}
$$
\begin{code}
 | otherwise                  =  bindVarToTerm vP tC bind
 where
   vPmr = lookupVarTables vts vP
\end{code}

\subsubsection{Bound Pattern Variable}
$$
\inferrule
   { v_P \in B_P
     \and
     t_C = v_C
     \and
     v_C \in B_C
   }
   {\beta;(B_C,B_P) \vdash t_C :: v_P
    \leadsto \beta \uplus \{ v_P \mapsto v_C \}}
   \quad
   \texttt{vMatch Bound-Var}
$$
\begin{code}
bvMatch :: Monad m => [VarTable] -> Binding -> CBVS
        -> Candidate -> Variable -> m Binding
-- we know vP is in pbvs
bvMatch vts bind cbvs (Var _ vC) vP
 | StdVar vC `S.member` cbvs  =  bindVarToVar vP vC bind
 | otherwise  =  fail "bvMatch: candidate not a bound variable"
\end{code}

\newpage
\subsubsection{Known Pattern Variable}

\begin{code}
kvMatch :: Monad m => [VarTable] -> Binding
       ->  Candidate -> VarMatchRole -> TermKind -> Variable -> m Binding
-- know vP is not in pbvs, in vts, and it maps to whatP
\end{code}
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C = V~v_C
     \and
     v_P = v_C
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
   \leadsto
   \beta \uplus \{ v_P \mapsto v_P \}}
   \quad
   \texttt{vMatch Known-Var-Refl}
$$
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C = V~v_C
     \and
     t_C = \kappa s(v_P)
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto v_C \}}
   \quad
   \texttt{vMatch Known-Var-Var}
$$
\begin{code}
-- know vP is not in pbvs, in vts, and it maps to whatP
kvMatch vts bind tC@(Var _ vC) whatP tkP vP
 | vC == vP                                    =  bindVarToVar vP vP bind
 | isKnownConst whatP && tC == vmrConst whatP  =  bindVarToVar vP vC bind
\end{code}
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C \neq V~v_c
     \and
     t_C = \kappa s(v_P)
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}}
   \quad
   \texttt{vMatch Known-Var-TVal}
$$
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C : T
     \and
     \kappa s(v_P) : T
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}}
   \quad
   \texttt{vMatch Known-Var-TType}
$$
\begin{code}
-- know vP is not in pbvs, in vts, and it maps to whatP
kvMatch vts bind tC whatP tkP vP
 | isKnownConst whatP && tC == vmrConst whatP     =  bindVarToTerm vP tC bind
 | isExprKind tkP && isKnownVar whatP
   && vmrType whatP == ekType tkP                 =  bindVarToTerm vP tC bind
kvMatch _ _ _ _ _ _ = fail "kvMatch: candidate not this known variable."
\end{code}

\newpage
\subsection{Variable-Set Matching}

\begin{code}
vsMatch :: MonadPlus mp => [VarTable] -> Binding -> CBVS -> PBVS
        -> VarSet -> VarSet -> mp Binding
-- vsC `subset` cbvs && vsP `subset` pbvc
vsMatch vts bind cbvs pbvc vsC vsP  = fail "vsMatch: N.Y.I."
\end{code}

\newpage
\subsection{Variable-List Matching}

\begin{code}
vlMatch :: MonadPlus mp => [VarTable] -> Binding -> CBVS -> PBVS
        -> VarList -> VarList -> mp Binding
-- vsC `subset` cbvs && vsP `subset` pbvc
vlMatch vts bind cbvs pbvc vlC vlP  = fail "vlMatch: N.Y.I."
\end{code}

\newpage
\subsection{Substitution Matching}

\begin{code}
sMatch vts bindT cbvs pbvs subC subP = fail "sMatch: N.Y.I"
\end{code}