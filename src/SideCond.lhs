\section{Side Conditions}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module SideCond (
  SideCond, AtmSideCond
, pattern Disjoint, pattern Exact, pattern Covers
, pattern IsPre, pattern Fresh
-- , pattern Exact, pattern Approx
-- , pattern Disjoint, pattern Covers, pattern DisjCov, pattern PreDisj
-- , vscTrue
-- , addPreSC, addExactSC, addDisjSC, addCoverSC, checkNewSC
--, VarSCMap
, scTrue
-- , pattern SC, pattern Fresh, pattern VarSCs, sidecond
, mrgAtmCond, mrgSideCond
, scDischarged
, notin, is, covers, fresh, pre
, int_tst_SideCond
) where
import Data.Char
import Data.List
import Data.Maybe (fromJust)
import Data.Set(Set)
import qualified Data.Set as S
import Data.Map(Map)
import qualified Data.Map as M

import Utilities
import LexBase
import Variables

import Test.HUnit
import Test.Framework as TF (defaultMain, testGroup, Test)
import Test.Framework.Providers.HUnit (testCase)
--import Test.Framework.Providers.QuickCheck2 (testProperty)
\end{code}


\subsection{Introduction}

A side-condition is a property used in laws,
typically putting a constraint on the free variables of some term.
In many logics, these can be checked by simple inspection of a term.
However,
given a logic like ours with explict expression and predicate
(a.k.a. \emph{schematic}) variables this is not always possible.

A side condition is about a relationship between the free variables
of term ($T$),
and a set of other (general) variables ($x,\lst{v}$).
In general with have a conjunction of atomic conditions,
but we need to be able to distinguish between no conditions (always ``true'')
and inconsistent conditions
(e.g. $x \notin \fv(T) \land x = \fv(T) $, always ``false'').
As a false side-condition means a match failure,
we do not represent them explicitly.
Instead, any operation on side-conditions that could result
in an inconsistent result should fail, gracefully.
\begin{code}
type SideCond = [AtmSideCond] -- [] is "true"
\end{code}
An atomic condition can have the form:
\begin{eqnarray*}
   x,\lst v   \notin  \fv(T)
   && \mbox{disjoint, short for }\{x,\lst v\} \cap \fv(T) = \emptyset
\\ x,\lst v      =    \fv(T) && \mbox{exact}
\\ x,\lst v \supseteq \fv(T) && \mbox{covering}
\\ pre      \supseteq \fv(T) && \mbox{pre-condition, no dashed variables}
\end{eqnarray*}
In most cases the term $T$ will be very general,
and will be represented by a variable.
In some cases, we will use a list-variable to denoted a list of terms,
usually expressions, and we will expect there to be only one general variable
which will itself be a list variable:
\begin{eqnarray*}
   \lst v   \notin  \fv(\lst e) && \mbox{disjoint, short for }
   v_1\notin \fv(e_1) \land \dots \land v_n\notin \fv(e_n)
\\ \lst v      =    \fv(\lst e) && \mbox{exact, short for }
   \{v_1\}= \fv(e_1) \land \dots \land \{v_n\} =  \fv(e_n)
\end{eqnarray*}
This arises when we have side-conditions between lists of variables
and expressions that occur in substitutions.
\begin{code}
data AtmSideCond
 = SD GenVar VarSet -- Disjoint
 | SE GenVar VarSet -- Equals
 | SS GenVar VarSet -- Superset (covers)
 | SP GenVar        -- Pre
 | FR VarSet        -- FResh variables
 deriving (Eq,Ord,Show,Read)

pattern Disjoint gv vs = SD gv vs  --  vs `intersect`  gv = {}
pattern Exact    gv vs = SE gv vs  --  vs      =       gv
pattern Covers   gv vs = SS gv vs  --  vs `supersetof` gv
pattern IsPre    gv    = SP gv
pattern Fresh       vs = FR vs
\end{code}
We also need to say that some variables are fresh.
This is not a relation involving a specified term,
but instead the entire term to which this side-condition is attached.

Sometimes we want the \texttt{GenVar} component
\begin{code}
ascGVar :: AtmSideCond -> Maybe GenVar
ascGVar (Disjoint gv _)  =  Just gv
ascGVar (Exact gv _)     =  Just gv
ascGVar (Covers gv _)    =  Just gv
ascGVar _                =  Nothing
\end{code}



% \newpage
% \subsubsection{Variable side-conditions}
% So, a side-condition associated with a term variable is either exact (\texttt{X}),
% or approximate (\texttt{A}):
% \begin{code}
% data VarSideCond
%  = X VarSet
%  | A Bool -- true if term must be a pre-condition
%      (Maybe VarSet) -- D
%      (Maybe VarSet) -- C
%  deriving (Eq,Ord,Show,Read)
%
% pattern Exact vs = X vs
% pattern Approx pre mD mC <- A pre mD mC
% pattern Disjoint d <- A _ (Just d) _
% pattern Covers c <- A _ _ (Just c)
% pattern DisjCov d c <- A _ (Just d) (Just c)
% pattern PreDisj pre d <- A pre (Just d) _
% \end{code}
%
% Typically a variable side-condition will be built
% from fragments that specify one of $pre$, $D$, $X$ or $C$,
% starting with a condition where all parts are ``null'',
% signalling a trivially true side-condition.
% \begin{code}
% vscTrue :: VarSideCond
% vscTrue = A False Nothing Nothing
% \end{code}

We will want to merge a set with a maybe-set below:
\begin{code}
mrgSet  :: Ord a
          => (Set a -> Set a -> Set a) -> Set a -> Maybe (Set a)
          -> Set a
mrgSet op s Nothing    =  s
mrgSet op s (Just s')  =  s `op` s'

jmrgSet op s ms = Just $ mrgSet op s ms
\end{code}

Variable Side-Condition test values:
\begin{code}
i_a = fromJust $ ident "a"
i_b = fromJust $ ident "b"
i_e = fromJust $ ident "e"
i_f = fromJust $ ident "f"

v_a =  PreVar    $ i_a
v_b =  PreVar    $ i_b
v_a' = PostVar   $ i_a
v_b' = PostVar   $ i_b

gv_a =  StdVar v_a
gv_b =  StdVar v_b
gv_a' = StdVar v_a'
gv_b' = StdVar v_b'

s0   = S.fromList [] :: VarSet
sa   = S.fromList [gv_a]
sa'  = S.fromList [gv_a']
sb   = S.fromList [gv_b]
sab  = S.fromList [gv_a,gv_b]
saa' = S.fromList [gv_a,gv_a']
sab' = S.fromList [gv_a,gv_b']
sbb' = S.fromList [gv_b,gv_b']

-- sc_pre          =  A True Nothing Nothing
-- sc_exact_a      =  Exact sa
-- sc_exact_b      =  Exact sb
-- sc_exact_ab     =  Exact sab
-- sc_exact_ab'    =  Exact sab'
-- sc_cover_a      =  A False Nothing $ Just sa
-- sc_cover_ab     =  A False Nothing $ Just sab
-- sc_cover_ab'    =  A False Nothing $ Just sab'
-- sc_disjoint_a   =  A False (Just sa) Nothing
-- sc_disjoint_b   =  A False (Just sb) Nothing
-- sc_disjoint_ab  =  A False (Just sab) Nothing
-- sc_D_a_C_b      =  A False (Just sa) (Just sb)
-- sc_D_a_C_bb'    =  A False (Just sa) (Just sbb')
\end{code}

% \newpage
% \paragraph{Adding $pre$:} check against any pre-existing $X$ or $C$
% \begin{code}
% addPreSC :: Monad m => VarSideCond -> m VarSideCond
%
% addPreSC vsc@(Exact x)
%  | isPreVarSet x   =  return vsc
%  | otherwise       =  fail "SideCond.addPreSC: exact set is not a precondition"
%
% addPreSC vsc@(Covers vs)
%  | isPreVarSet vs   =  return vsc
%  | otherwise        =  fail "SideCond.addPreSC: covering set is not a precondition"
%
% addPreSC (Approx _ mD mC) = return $ A True mD mC
% \end{code}

Tests:
\begin{code}
-- test_add_pre_to_true = testCase "Add pre to trivial SC"
--  ( addPreSC vscTrue  @?=  Just sc_pre )
--
-- test_add_pre_to_exact_ok = testCase "Add pre to exact SC (OK)"
--  ( addPreSC sc_exact_ab  @?=  Just sc_exact_ab )
--
-- test_add_pre_to_exact_fail = testCase "Add pre to exact SC (Fail)"
--  ( addPreSC sc_exact_ab'  @?=  Nothing )
--
-- test_add_pre_to_cover_ok = testCase "Add pre to cover SC (OK)"
--  ( addPreSC sc_cover_ab  @?=  Just sc_cover_ab )
--
-- test_add_pre_to_cover_fail = testCase "Add pre to cover SC (Fail)"
--  ( addPreSC sc_cover_ab'  @?=  Nothing )
--
-- test_add_pre_to_disjoint = testCase "Add pre to disjoint"
--  ( addPreSC sc_disjoint_ab  @?=  Just (A True (Just sab) Nothing) )
--
-- addPreTests = testGroup "SideCond.addPreSC"
--                [ test_add_pre_to_true
--                , test_add_pre_to_exact_ok
--                , test_add_pre_to_exact_fail
--                , test_add_pre_to_cover_ok
--                , test_add_pre_to_cover_fail
--                , test_add_pre_to_disjoint
--                ]
\end{code}

% \newpage
% \paragraph{Adding $D$:} check against any pre-existing $X$ or $C$
% \begin{code}
% addDisjSC :: Monad m => VarSet -> VarSideCond -> m VarSideCond
%
% addDisjSC d vsc@(Exact x)
%  | d `disjoint` x  =  return vsc
%  | otherwise       =  fail "SideCond.addDisjSC: exact and disjoint sets overlap"
%
% addDisjSC d (Approx pre mD mC@(Just c))
%  | c `disjoint` d  =  return $ A pre (jmrgSet S.union d mD) mC
%  | otherwise       =  fail "SideCond.addDisjSC: covering and disjoint sets overlap"
%
% addDisjSC d (Approx pre mD mC)
%   = return $ A pre (jmrgSet S.union d mD) mC
% \end{code}
%
% Tests:
% \begin{code}
% test_add_disj_to_true = testCase "Add disjoint to trivial SC"
%  ( addDisjSC sab vscTrue  @?=  Just sc_disjoint_ab)
%
% test_add_disj_to_exact_ok = testCase "Add disjoint to exact (Ok)"
%  ( addDisjSC sb sc_exact_a  @?=  Just sc_exact_a )
%
% test_add_disj_to_exact_fail = testCase "Add disjoint to exact (Fail)"
%  ( addDisjSC sb sc_exact_ab  @?=  Nothing )
%
% test_add_disj_to_cover_ok = testCase "Add disjoint to cover (Ok)"
%  ( addDisjSC sb sc_cover_a  @?=  Just (A False (Just sb) (Just sa)) )
%
% test_add_disj_to_cover_fail = testCase "Add disjoint to cover (Fail)"
%  ( addDisjSC sb sc_cover_ab  @?=  Nothing )
%
% test_add_disj_to_disj = testCase "Add disjoint to disjoint"
%  ( addDisjSC sa sc_disjoint_b  @?=  Just sc_disjoint_ab )
%
% test_add_disj_to_mixed = testCase "Add disjoint to disjoint and cover"
%  ( addDisjSC sa' sc_D_a_C_b  @?=  Just (A False (Just saa') (Just sb)) )
%
% addDisjTests = testGroup "SideCond.addDisjSC"
%                [ test_add_disj_to_true
%                , test_add_disj_to_exact_ok
%                , test_add_disj_to_exact_fail
%                , test_add_disj_to_cover_ok
%                , test_add_disj_to_cover_fail
%                , test_add_disj_to_disj
%                , test_add_disj_to_mixed
%                ]
% \end{code}

% \newpage
% \paragraph{Adding $X$:} check against any pre-existing $pre$, $D$, $X$ or $C$
% \begin{code}
% addExactSC :: Monad m => VarSet -> VarSideCond -> m VarSideCond
%
% addExactSC x vsc@(Exact x0)
%  | x == x0    =  return vsc
%  | otherwise  =  fail "SideCond.addExactSC: differing exact sets"
%
% addExactSC x (Approx pre _ _)
%  | pre && not (isPreVarSet x) = fail "SideCond.addExactSC: exact set not pre-condition"
%
% addExactSC x (Disjoint d)
%  | x `overlaps` d = fail "SideCond.addExactSC: exact and disjoint sets overlap"
%
% addExactSC x (Covers c)
%  | not(x `S.isSubsetOf` c) = fail "SideCond.addExactSC: exact not inside covering set"
%
% addExactSC x _ = return $ Exact x
% \end{code}
%
% Tests:
% \begin{code}
% test_add_exact_to_true = testCase "Add exact to trivial SC"
%  ( addExactSC sab vscTrue  @?=  Just sc_exact_ab)
%
% test_add_exact_to_exact_ok = testCase "Add exact to exact (Ok)"
%  ( addExactSC sa sc_exact_a  @?=  Just sc_exact_a )
%
% test_add_exact_to_exact_fail = testCase "Add exact to exact (Fail)"
%  ( addExactSC sb sc_exact_ab  @?=  Nothing )
%
% test_add_exact_to_cover_ok = testCase "Add exact to cover (Ok)"
%  ( addExactSC sa sc_cover_ab  @?=  Just sc_exact_a )
%
% test_add_exact_to_cover_fail = testCase "Add exact to cover (Fail)"
%  ( addExactSC sb sc_cover_a  @?=  Nothing )
%
% test_add_exact_to_disj = testCase "Add exact to disjoint"
%  ( addExactSC sa sc_disjoint_b  @?=  Just sc_exact_a )
%
% test_add_exact_to_mixed = testCase "Add exact to disjoint and cover"
%  ( addExactSC sb sc_D_a_C_b  @?=  Just sc_exact_b )
%
% addExactTests = testGroup "SideCond.addExactSC"
%                [ test_add_exact_to_true
%                , test_add_exact_to_exact_ok
%                , test_add_exact_to_exact_fail
%                , test_add_exact_to_cover_ok
%                , test_add_exact_to_cover_fail
%                , test_add_exact_to_disj
%                , test_add_exact_to_mixed
%                ]
% \end{code}

% \newpage
% \paragraph{Adding $C$:} check against any pre-existing $pre$, $D$, or $X$
% \begin{code}
% addCoverSC :: Monad m => VarSet -> VarSideCond -> m VarSideCond
%
% addCoverSC c vsc@(Exact x)
%  | x `S.isSubsetOf` c  =  return vsc
%  | otherwise           =  fail "SideCond.addCoverSC: exact set not inside covering set"
%
% addCoverSC c (Approx pre _ _)
%  | pre && not (isPreVarSet c) = fail "SideCond.addCoverSC: cover set not pre-condition"
%
% addCoverSC c (Disjoint d)
%  | c `overlaps` d = fail "SideCond.addCoverSC: cover and disjoint sets overlap"
%
% addCoverSC c (Approx pre mD mC)
%  | S.null c'  =  return $ Exact S.empty
%  | otherwise  =  return $ A pre mD $ Just c'
%  where c' = mrgSet S.intersection c mC
% \end{code}
%
% Tests:
% \begin{code}
% test_add_cover_to_true = testCase "Add cover to trivial SC"
%  ( addCoverSC sab vscTrue  @?=  Just sc_cover_ab)
%
% test_add_cover_to_exact_ok = testCase "Add cover to exact (Ok)"
%  ( addCoverSC sab sc_exact_a  @?=  Just sc_exact_a )
%
% test_add_cover_to_exact_fail = testCase "Add cover to exact (Fail)"
%  ( addCoverSC sb sc_exact_ab  @?=  Nothing )
%
% test_add_cover_to_cover_c = testCase "Add cover to cover (still cover)"
%  ( addCoverSC sa sc_cover_ab  @?=  Just sc_cover_a )
%
% test_add_cover_to_cover_x = testCase "Add cover to cover (exact)"
%  ( addCoverSC sb sc_cover_a  @?=  Just (Exact s0) )
%
% test_add_cover_to_disj = testCase "Add cover to disjoint"
%  ( addCoverSC sb sc_disjoint_a  @?=  Just sc_D_a_C_b )
%
% test_add_cover_to_mixed = testCase "Add cover to disjoint and cover"
%  ( addCoverSC sb sc_D_a_C_bb'  @?=  Just sc_D_a_C_b )
%
% addCoverTests = testGroup "SideCond.addCoverSC"
%                [ test_add_cover_to_true
%                , test_add_cover_to_exact_ok
%                , test_add_cover_to_exact_fail
%                , test_add_cover_to_cover_c
%                , test_add_cover_to_cover_x
%                , test_add_cover_to_disj
%                , test_add_cover_to_mixed
%                ]
% \end{code}

% \subsubsection{Variable condition-add tests}
% \begin{code}
% varSCTests = testGroup "Adding Variable Side-Conditions"
%                 [ addPreTests
%                 , addDisjTests
%                 , addExactTests
%                 , addCoverTests
%                 ]
% \end{code}

% \subsubsection{Merging Variable Conditions}
%
% \begin{code}
% mrgVarSideCond :: Monad m => VarSideCond -> VarSideCond -> m VarSideCond
% mrgVarSideCond (X vs) vsc = addExactSC vs vsc
% mrgVarSideCond (A pre mD mC) vsc
%  = do vsc1 <- mrgD mD vsc
%       vsc2 <- mrgC mC vsc1
%       if pre then addPreSC vsc2 else return vsc2
%  where
%    mrgD Nothing vsc   =  return vsc
%    mrgD (Just d) vsc  =  addDisjSC d vsc
%    mrgC Nothing vsc   =  return vsc
%    mrgC (Just c) vsc  =  addCoverSC c vsc
% \end{code}


\subsection{Full Side Conditions}


If the atomic condition list is empty,
then we have the trivial side-condition, which is always true:
\begin{code}
scTrue :: SideCond
scTrue = []
\end{code}

Test values:
\begin{code}
v_e  = StdVar $ PreExpr  $ i_e
v_f  = StdVar $ PreExpr  $ i_f
v_e' = StdVar $ PostExpr $ i_e
v_f' = StdVar $ PostExpr $ i_f
\end{code}

Pattern synonyms and builder
\begin{code}
-- pattern SideCond n vmap <- SC n vmap
-- pattern Fresh n <- SC n _
-- pattern VarSCs vmap <- SC _ vmap

-- sidecond :: Monad m => VarSet -> VarSCMap -> m SideCond
-- sidecond n vmap
--  | all (checkNewSC n) $ M.elems vmap  =  return $ SC n vmap
--  | otherwise  =  fail "fresh set conflicts with variable side-condition"
\end{code}

% Checking $N$ against a variable-side condition, looking at $X$ and $C$.
% \begin{code}
% checkNewSC :: VarSet -> VarSideCond -> Bool
% checkNewSC n (Exact x)   =  n `disjoint` x
% checkNewSC n (Covers c)  =  n `disjoint` c
% checkNewSC _ _           =  True
% \end{code}


Tests:
\begin{code}
-- test_sidecond_empty = testCase "Trivial side-condition"
--  ( sidecond S.empty M.empty @?=  Just scTrue)
--
-- test_sidecond_freshonly = testCase "Only Freshness"
--  ( sidecond sab M.empty @?=  Just (SC sab M.empty) )
--
-- test_sidecond_one_pre = testCase "One Precondition"
--  ( sidecond S.empty m_e_pre @?=  Just (SC S.empty m_e_pre) )
--
-- test_sidecond_fresh_exact_ok = testCase "Freshness and Exact (Ok)"
--  ( sidecond sb m_e_exact_a @?=  Just (SC sb m_e_exact_a) )
--
-- test_sidecond_fresh_exact_fail = testCase "Freshness and Exact (Fail)"
--  ( sidecond sa m_e_exact_a @?=  Nothing )
--
-- test_sidecond_fresh_cover_ok = testCase "Freshness and Cover (Ok)"
--  ( sidecond sb m_e_cover_a @?=  Just (SC sb m_e_cover_a) )
--
-- test_sidecond_fresh_cover_fail = testCase "Freshness and Cover (Fail)"
--  ( sidecond sa m_e_cover_a @?=  Nothing )
--
-- test_sidecond_fresh_exact_cover_fail = testCase "Freshness, Exact and Cover (Fail)"
--  ( sidecond sa m_e_X_b_f_C_ab @?=  Nothing )
--
-- test_sidecond_fresh_disjoint = testCase "Freshness and Disjoint"
--  ( sidecond saa' m_e_disjoint_ab @?=  Just (SC saa' m_e_disjoint_ab) )
--
sidecondTests = testGroup "SideCond.sidecond" []
--                [ test_sidecond_empty
--                , test_sidecond_freshonly
--                , test_sidecond_one_pre
--                , test_sidecond_fresh_exact_ok
--                , test_sidecond_fresh_exact_fail
--                , test_sidecond_fresh_cover_ok
--                , test_sidecond_fresh_cover_fail
--                , test_sidecond_fresh_exact_cover_fail
--                , test_sidecond_fresh_disjoint
--                ]
\end{code}

\newpage
\subsection{Merging Side-Conditions}

Merging side-conditions is tricky,
mainly because we have 5 variants giving us 15 combinations,
allowing for symmetry.
1 variant (freshness), has no associated general variable,
so applies universally.
The others only interact when associated with the same general variable.

We support only one way to assemble a side-condition from atomic ones.
This uses 5 functions to do the work, one for each atomic variant.
\begin{code}
mrgAtmCond :: Monad m => AtmSideCond -> SideCond -> m SideCond
mrgAtmCond (Fresh       vs) ascs  =  mrgFresh vs ascs
mrgAtmCond (IsPre    gv)    ascs
  =  splice (mrgIsPre gv) $ brkspn (cites gv) ascs
mrgAtmCond (Disjoint gv vs) ascs
  =  splice (mrgDisjoint gv vs) $ brkspn (cites gv) ascs
mrgAtmCond (Exact    gv vs) ascs
  =  splice (mrgExact gv vs) $ brkspn (cites gv) ascs
mrgAtmCond (Covers   gv vs) ascs
  =  splice (mrgCovers gv vs) $ brkspn (cites gv) ascs

cites _  (Fresh _)         =  False
cites gv (IsPre gv')       =  gv == gv'
cites gv (Disjoint gv' _)  =  gv == gv'
cites gv (Exact gv' _)     =  gv == gv'
cites gv (Covers gv' _)    =  gv == gv'

brkspn p xs = let
                (before,rest) = break p xs
                (found,after) = span  p xs
              in (before,found,after)

splice mrg (before,found,after)
  = do found' <- mrg found
       return (before++found'++after)
\end{code}

Merging two side-conditions is then straightforward:
\begin{code}
mrgSideCond :: Monad m => SideCond -> SideCond -> m SideCond
mrgSideCond ascs1 [] = return ascs1
mrgSideCond ascs1 (asc:ascs2)
     = do ascs1' <- mrgAtmCond asc ascs1
          mrgSideCond ascs1' ascs2
\end{code}

The tricky part is merging atomic side-conditions into a sequence
of them.

Freshness will get done, when needed
\begin{code}
mrgFresh       vs ascs            =  fail "mrgFresh NYI"
\end{code}

Here, \texttt{found} is all atomic side conditions
that refer to \texttt{gv}.


Is a (pre-)Condition will get done, when needed
\begin{code}
mrgIsPre    gv    found  =  fail "mrgIsPre NYI"
\end{code}

\begin{eqnarray*}
   D_1 \land D_2 &=&  D_1 \cup D_2
\\ D_1 \land C_2 &=&  D_1 \land C_2 \setminus D_1
\\ D_1 \land X_2 &=&  D_1 \land X_2 \cond{~D_1 \cap X_2 = \emptyset~} \bot
\\ D_1 \land pre &=&  D_1 \land pre
\end{eqnarray*}
\begin{code}
mrgDisjoint gv vs [] = return [ Disjoint gv vs ]
mrgDisjoint gv vs1 (Disjoint _ vs2 : ascs)
  = do let vs' = vs1 `S.union` vs2
       mrgDisjoint gv vs' ascs
mrgDisjoint gv vs (_: ascs) = fail "mrgDisjoint NYfI"
\end{code}

Exactness will get done, when needed
\begin{code}
mrgExact    gv vs found  =  fail "mrgExact NYI"
\end{code}

Covering will get done, when needed
\begin{code}
mrgCovers   gv vs found  =  fail "mrgCovers NYI"
\end{code}

\begin{code}
\end{code}
Easy cases first --- merging same
\begin{code}
-- mrgAtmAtm (Fresh vs1) (Fresh vs2) = return (True,Fresh (vs1 `S.union` vs2))
-- mrgAtmAtm (IsPre gv1) a@(IsPre gv2)
--  | gv1 == gv2  = return (True, a)
-- mrgAtmAtm (Disjoint gv1 vs1) (Disjoint gv2 vs2)
--  | gv1 == gv2  = return (True, Disjoint gv2 (vs1 `S.union` vs2))
-- mrgAtmAtm (Exact gv1 vs1) a@(Exact gv2 vs2)
--  | gv1 == gv2 = if vs1 == vs2
--                 then return (True, a )
--                 else fail "inconsistent exact side-cond."
-- mrgAtmAtm (Covers gv1 vs1) (Covers gv2 vs2)
--  | gv1 == gv2  = return (True, Covers gv2 (vs1 `S.intersection` vs2))
\end{code}

\newpage
\subsection{Side-condition Implication}

We want to determine if one side-condition implies another.
We have something of the form:
\begin{eqnarray*}
 a_1 \land \dots \land a_m &\implies& c_1 \land \dots \land c_n
\end{eqnarray*}
where $a_i$ are the antecedent (match candidate) atomic side-conditions,
and $c_j$
are those of the consequent (match pattern mapped by match binding)
atomic side-conditions.
This corresponds to showing the validity of:
\begin{eqnarray*}
 \lnot a_1 \lor \dots \lor \lnot a_m &\lor& c_1 \land \dots \land c_n
\end{eqnarray*}
There are some obvious optimisations:
\begin{enumerate}
  \item Having $n=0$ means the consequent is true, so we are valid.
  \item Having $m=0$ means the antecedent is true,
         so requiring $n=0$ for validity to hold.
  \item Having $a_i=c_j$ means that we can remove $c_j$
  \item Having $a_i \implies c_j$ means that we can remove $c_j$.
  \item Having $a_i \implies \lnot c_j$ means that we cannot be valid.
  \item If there is no $a_i$ that implies a given $c_j$,
        then we cannot be valid.
\end{enumerate}
\begin{code}
scDischarged :: SideCond -> SideCond -> Bool
scDischarged anteSC []      =  True                               -- 1 above
scDischarged []     cnsqSC  =  False                              -- 2 above
scDischarged anteSC cnsqSC  =  scDisch3 anteSC (cnsqSC \\ anteSC) -- 3 above

scDisch3     anteSC []      =  True                               -- 1,3 above
scDisch3     []     cnsqSC  =  False                              -- 2 above
scDisch3     anteSC (cnsqASC:cnsqASCs)                            -- 4-6 above
  = ascDisch456 cnsqASC anteSC
    &&
    scDisch3 anteSC cnsqASCs

ascDisch456 _ []            =  False                              -- 6 above
ascDisch456 cnsqASC (anteASC:anteASCs)
  = case ascImplies cnsqASC anteASC of
      Just b                -> b                                  -- 4,5 above
      Nothing               -> ascDisch456 cnsqASC anteASCs       -- 6 above
\end{code}

Given an $a_i$ and $c_j$, there are three possibilities of interest:
$a_i \implies c_j$, $a_i \implies \lnot c_j$, or neither of these two holds.
The first two possibilites allow \texttt{ascDisch456} to return a conclusion.
The third means we need to keep searching the $a_i$s.

We note that an \texttt{IsPre} atomic side-condition
can only imply itself,
so will have been swept up earlier by 3 above.
Any two of the remaining kinds of atomic side-condition can only interact
as per 4 or 5 above, if they have the same general variable.
\begin{code}
ascImplies :: AtmSideCond -> AtmSideCond -> Maybe Bool
ascImplies cnsqASC anteASC
 | ascGVar cnsqASC == ascGVar anteASC  =  cnsqASC `ascimp` anteASC
ascImplies _       _                   =  Nothing
\end{code}

\newpage
\subsubsection{SC Implication by cases}

Given (candidate) atomic side-condition $c$,
and (pattern) atomic side-condition $p$,
we want to know if we can assert
$$ c \implies p \qquad\textrm{or}\qquad c \implies \lnot p$$
or lack enough information to decide these.
\begin{code}
ascimp :: AtmSideCond -> AtmSideCond -> Maybe Bool
\end{code}

We assume here that $U$ is the ``universe'' of all variables
(i.e. all the variables free in the conjecture being proven).
Its occurence below means that deciding the implication
is not feasible without global knowledge
of the whole proof goal.
Note also that $v$ is a variable set in general.
We use $A \disj B$ as short for $A \cap B = \emptyset$,
and where a predicate is expected, use $A \cap B$
to denote $A \cap B \neq \emptyset$.


%% Disjoint => ...

\paragraph{Disjoint implies Disjoint}
\begin{eqnarray*}
   C \disj v \implies  P \disj v &\textrm{if}& C \supseteq P
\\ C \disj v \implies  P \cap v  && \textrm{insufficient info.}
\end{eqnarray*}
\begin{code}
(Disjoint _ vsC) `ascimp` (Disjoint _ vsP)
  |  vsP `S.isSubsetOf` vsC  =  Just True
\end{code}

\paragraph{Disjoint implies Exact}
\begin{eqnarray*}
   C \disj v \implies  P = v    && \textrm{insufficient info.}
\\ C \disj v \implies  P \neq v &\textrm{if}& C \cap P
\end{eqnarray*}
\begin{code}
(Disjoint _ vsC) `ascimp` (Exact _ vsP)
  |  vsP `overlaps` vsC  =  Just False
\end{code}

\paragraph{Disjoint implies Covers}
\begin{eqnarray*}
   C \disj v \implies  P \supseteq v     && \textrm{insufficient info.}
\\ C \disj v \implies  P \not\supseteq v && \textrm{insufficient info.}
\end{eqnarray*}


%% Exact => ...

\paragraph{Exact implies Disjoint}
\begin{eqnarray*}
   C = v \implies  P \disj v   &\textrm{if}& C \disj P
\\ C = v \implies  P \cap v    &\textrm{if}& C \cap P
\end{eqnarray*}
\begin{code}
(Exact _ vsC) `ascimp` (Disjoint _ vsP) =  Just (vsC `disjoint` vsP)
\end{code}

\paragraph{Exact implies Exact}
\begin{eqnarray*}
   C = v \implies  P = v     &\textrm{if}& C = P
\\ C = v \implies  P \neq v  &\textrm{if}& C \neq P
\end{eqnarray*}
\begin{code}
(Exact _ vsC) `ascimp` (Exact _ vsP) =  Just (vsC == vsP)
\end{code}

\paragraph{Exact implies Covers}
\begin{eqnarray*}
   C = v \implies  P \supseteq v      &\textrm{if}& C \subseteq P
\\ C = v \implies  P \not\supseteq v  &\textrm{if}& C \not\subseteq P
\end{eqnarray*}
\begin{code}
(Exact _ vsC) `ascimp` (Covers _ vsP) =  Just (vsC `S.isSubsetOf` vsP)
\end{code}


%% Covers => ...

\paragraph{Covers implies Disjoint}
\begin{eqnarray*}
   C \supseteq v \implies  P \disj v   &\textrm{if}& C \disj P
\\ C \supseteq v \implies  P \cap v    && \textrm{insufficient info.}
\end{eqnarray*}
\begin{code}
(Covers _ vsC) `ascimp` (Disjoint _ vsP)
  |  vsP `disjoint` vsC  =  Just True
\end{code}

\paragraph{Covers implies Exact}
\begin{eqnarray*}
   C \supseteq v \implies  P = v    && \textrm{insufficient info.}
\\ C \supseteq v \implies  P \neq v &\textrm{if}& C \not\supseteq P
\end{eqnarray*}
\begin{code}
(Covers _ vsC) `ascimp` (Exact _ vsP)
  |  not(vsP `S.isSubsetOf` vsC)  =  Just False
\end{code}

\paragraph{Covers implies Cover}
\begin{eqnarray*}
   C \supseteq v \implies  P \supseteq v     & \textrm{if}& C \subseteq P
\\ C \supseteq v \implies  P \not\supseteq v && \textrm{insufficient info.}
\end{eqnarray*}
\begin{code}
(Covers _ vsC) `ascimp` (Covers _ vsP)
  |  vsC `S.isSubsetOf` vsP  =  Just True
\end{code}




\begin{code}
-- Disjoint _ vs
-- Exact    _ vs
-- Covers   _ vs
-- Fresh      vs
\end{code}




Anything else results in no strong conclusion:
\begin{code}
ascimp _ _ = Nothing -- for now
\end{code}

\newpage
\subsection{Building side-conditions.}

We want to provide constructors that match how we typically
specify side-condtions, as a conjunction of the following forms:

\begin{eqnarray*}
   x,\lst v   \notin  \fv(T) && \mbox{disjoint}
\\ x,\lst v      =    \fv(T) && \mbox{exact}
\\ x,\lst v \supseteq \fv(T) && \mbox{covering}
\\ x,\lst v \mbox{ fresh}    && \mbox{freshness}
\\ pre      \supseteq \fv(T) && \mbox{pre-condition}
\end{eqnarray*}

All the code below relies on the fact that
\texttt{addDisjSC}, \texttt{addExactSC}, \texttt{addCoverSC},
and \texttt{addPreSC} always succeed
when their last argument is \texttt{vscTrue}.

$\lst v \notin \fv(T)$
\begin{code}
notin :: VarList -> GenVar -> SideCond
vl `notin` tV  =  [ Disjoint tV (S.fromList vl) ]
\end{code}

$\lst v = \fv(T)$
\begin{code}
is :: VarList -> GenVar -> SideCond
vl `is` tV  =  [ Exact tV (S.fromList vl) ]
\end{code}

$\lst v \supseteq \fv(T)$
\begin{code}
covers :: VarList -> GenVar -> SideCond
vl `covers` tV  =  [ Covers tV (S.fromList vl) ]
\end{code}

fresh $\lst v$
\begin{code}
fresh :: VarList -> SideCond
fresh vl  =  [ Fresh (S.fromList vl) ]
\end{code}

$pre \supseteq \fv(T)$
\begin{code}
pre :: GenVar -> SideCond
pre tV  = [ IsPre tV ]
\end{code}

\newpage
\subsection{Exported Test Group}
\begin{code}
int_tst_SideCond :: [TF.Test]
int_tst_SideCond
  = [ testGroup "\nSideCond Internal" [] ]
--      [ varSCTests
--      , sidecondTests
--      ]
--    ]
\end{code}
