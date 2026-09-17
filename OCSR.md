# Reading a skeletal structure — what was investigated, and what Build 5 ships

Build 5's scanner reads chemical **names**, **molecular formulas**, **SMILES**,
**InChI** and **InChIKey** from a page, live, with no shutter button. It does
**not** read skeletal structure diagrams, and the app says so on the scanner
screen rather than approximating one.

This document records why, what was evaluated, and exactly what would have to
be true before that changes. It exists because "we looked into it" is not a
finding, and because the decision not to ship a feature deserves the same
evidence as the decision to ship one.

## The thing itself

A skeletal (bond-line) formula is not text. Carbons are unlabeled vertices,
carbon–hydrogen bonds are implicit, bond order is carried by the number of
lines, stereochemistry by wedges and dashes, and aromaticity by a circle or by
alternating bonds that a reader is expected to recognize as a ring system.
Apple's Vision framework — and `DataScannerViewController`, which is what the
scanner uses — performs optical **character** recognition. Pointed at a
benzene ring it reads nothing, or it reads the heteroatom labels as loose
letters. It has no model of a molecular graph and cannot acquire one.

The discipline that does this is **Optical Chemical Structure Recognition**
(OCSR). Modern OCSR systems are image-to-sequence neural networks: a vision
encoder over the cropped diagram, a decoder that emits a machine-readable
structure, usually SMILES.

## What was evaluated

### MolScribe

The most interesting of the current generation, because of what it outputs.
Rather than emitting a SMILES string alone, MolScribe predicts an explicit
**atom and bond graph** with coordinates and a per-prediction confidence, and
derives SMILES from it. For this app that difference matters twice over:

* a graph can be checked for chemical validity before anything is shown;
* a confidence that is attached to the structure, rather than to a string, is
  what a reliability threshold can actually be applied to.

It is a Swin-Transformer encoder with a transformer decoder — order 100 M
parameters in the published checkpoints.

### DECIMER Image Transformer

The other serious open option, an EfficientNet/transformer image-to-SMILES
model with a large synthetic training corpus. Emits SMILES directly, so a
prediction is a string that either parses or does not; there is no partial
graph to inspect and no per-atom confidence to threshold on. Published
checkpoints are substantially larger than MolScribe's.

### Why not a hosted service

Several commercial OCSR APIs exist. Using one would mean **uploading a camera
frame of whatever the learner is pointing at** to a third party. That is a
different app with a different privacy policy, a different App Store privacy
declaration, a different data-retention answer and a consent flow this app
does not have. The brief for this build was explicit that such a change stops
and gets documented before it is implemented, and this is that stop: it was
not implemented, and the privacy statements in `PRIVACY.md` and on the website
remain true, namely that camera frames are processed on the device and are
never uploaded or stored.

## Why nothing shipped

Three requirements have to be met together, and none of them was met.

**1. The model has to be licensed for this.** A repository's MIT license
covers its code. It does not automatically cover separately hosted checkpoint
weights, which are frequently released under different terms — research-only
clauses are common — and the terms of the dataset the weights were trained on
can travel with them. Establishing that a specific checkpoint may be
redistributed inside an App Store binary means reading that checkpoint's own
license and its training data's provenance, and recording the result. That
audit has not been completed, so no weights were fetched and none are in the
repository. `PeriodicPro/Scanner/StructureRecognition.swift` carries the seam
where a licensed model would attach.

**2. It has to run on the device.** On-device is not a preference here, it is
the requirement that keeps the privacy claim true. That means a Core ML
conversion — `coremltools`, an ML Program, FP16, and as much of the graph on
the Neural Engine as the operator set allows — and then measurements of model
size, cold-load time, peak memory and inference latency on real iPhone
hardware. A model that adds hundreds of megabytes to the download, or that
takes seconds per inference, is not a live scanner whatever its accuracy.

**3. It has to be measured before it is believed.** The quality gate for this
feature is a benchmark of 50–100 real diagrams — clean PubChem depictions,
textbook screenshots, printed structures, rings and fused rings, aromatic
systems, heteroatoms, charges, stereochemistry, and the same again at an
angle, slightly blurred, and on different backgrounds — scored for valid
output rate, canonical-SMILES match, connectivity accuracy, confidence
calibration, and median and 95th-percentile latency. Only a measured
high-confidence accuracy justifies showing a learner a molecule and calling it
theirs.

**None of the three can be carried out in the environment this build was
produced in.** It has no network access to a model host, no macOS toolchain to
convert or compile a Core ML model, and no iPhone to measure one on. A
recognizer written here would have been an architecture with nothing behind
it and no idea how often it was right — which for a chemistry app is the worst
of the available options, because a confidently wrong molecule teaches a
learner something false.

So the honest thing shipped instead: the scanner does very well the part it
can do, and states plainly that it does not read diagrams.

## What the app says to the learner

From `StructureRecognition.swift`, shown on the scanner screen:

> Elemora reads chemical names, molecular formulas, SMILES, InChI and InChIKey
> from the page. Reading a skeletal diagram — working a molecule out from a
> bond-line drawing — needs a different kind of model, and Elemora does not
> ship one yet. It would rather say so than show you a molecule it guessed at.

## The route in, when the three requirements are met

1. Complete the license audit for a specific checkpoint: repository, code
   license, **weights** license, training-data provenance, required copyright
   and attribution notices, model version and file checksum. Record it in
   `DATA_SOURCES.md` and surface the notice in About → Data Sources.
2. Convert to Core ML and measure size, cold load, peak memory and latency on
   a realistic iPhone.
3. Run the 50–100 diagram benchmark and publish the numbers.
4. Implement `StructureRecognizer`, which already exists. The scanner calls it
   only for a region that has held still — never per frame — so the throttling
   is already in place.
5. Ship behind an explicit **Skeletal Structure Scan — Beta** treatment, with
   results below `reliabilityThreshold` never displayed.
6. A recognized structure is still only recognized. It goes through the same
   PubChem identity lookup a pasted SMILES string does, and where no exact
   record exists the app says "Structure recognized, but no exact PubChem
   identity was verified" — never "a new compound".
