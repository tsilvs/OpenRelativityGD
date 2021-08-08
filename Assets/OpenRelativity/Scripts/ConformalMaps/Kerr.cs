﻿using UnityEngine;

namespace OpenRelativity.ConformalMaps
{
    public class Kerr : Schwarzschild
    {
        public float spinMomentum;
        public Vector3 spinAxis = Vector3.up;

        protected float spinRadiusDiff = 0.0f;

        virtual public float aParam
        {
            get
            {
                return spinMomentum / (2 * state.gConst * Mathf.Pow(state.SpeedOfLight, 4.0f) * schwarzschildRadius);
            }
        }

        override public void SetEffectiveRadius(Vector3 piw)
        {
            if (spinMomentum <= SRelativityUtil.divByZeroCutoff)
            {
                return;
            }

            Quaternion rot = Quaternion.FromToRotation(spinAxis, Vector3.up);
            piw = rot * piw;

            float rs = schwarzschildRadius;
            float r = piw.magnitude;
            float cosInc = piw.z / r;
            float a = aParam;

            // I'm forced to approximate, for now. This might be avoided with tractable free fall coordinates.
            // This is a more accurate approximation, as (rs * r) tends >> (a * a * sinInc * sinInc),
            // such as at the equator or long radial distances.
            spinRadiusDiff = rs - (rs * r * r) / (r * r + a * a * cosInc);

            schwarzschildRadius -= spinRadiusDiff;
        }

        override public void ResetSchwarschildRadius()
        {
            if (spinMomentum <= SRelativityUtil.divByZeroCutoff)
            {
                return;
            }
            schwarzschildRadius += spinRadiusDiff;
            spinRadiusDiff = 0.0f;
        }

        virtual public float GetOmega(Vector3 piw)
        {
            float rSqr = piw.sqrMagnitude;
            // Radius:
            float r = Mathf.Sqrt(rSqr);
            // Inclination:
            float inc = Mathf.Acos(piw.z / r);
            // Azimuth:
            float azi = Mathf.Atan2(piw.y, piw.x);
            // Time: piw.w

            float a = spinMomentum / (schwarzschildRadius * state.planckMass / state.planckLength);
            float aSqr = a * a;
            float cosAzi = Mathf.Cos(azi);
            float sigma = rSqr + aSqr * cosAzi * cosAzi;

            float cosInc = Mathf.Cos(inc);
            float omega = (schwarzschildRadius * r * a * state.SpeedOfLight) / (sigma * (rSqr + aSqr) + schwarzschildRadius * r * aSqr * cosInc * cosInc);

            return omega;
        }

        virtual public float TimeCoordScale(Vector3 piw)
        {
            // If our "SetEffectiveRadius(piw)" is expected to be exact at the equator, but we use it in all cases,
            // Then we can better our overall approximation by assuming an inclincation-dependent time coordinate scaling.

            float a = aParam;
            float aSqr = a * a;

            float rSqr = piw.sqrMagnitude;
            // Radius:
            float r = Mathf.Sqrt(rSqr);
            // Inclination:
            float cosInc = piw.z / r;
            float cosIncSqr = cosInc * cosInc;
            float sinIncSqr = 1 - cosIncSqr;

            float rrrs = r * (r - schwarzschildRadius);

            return Mathf.Sqrt(
                (aSqr * cosIncSqr + rSqr) * ((aSqr + rSqr) * (aSqr + rSqr) + aSqr * sinIncSqr * (aSqr + rrrs)) /
                ((aSqr + rrrs) * (aSqr * cosIncSqr + rrrs))
            );
        }

        override public Comovement ComoveOptical(float properTDiff, Vector3 piw, Quaternion riw)
        {
            if ((spinMomentum <= SRelativityUtil.divByZeroCutoff) || (piw.sqrMagnitude <= SRelativityUtil.divByZeroCutoff))
            {
                return base.ComoveOptical(properTDiff, piw, riw);
            }

            // Adjust the global spin axis
            Quaternion rot = Quaternion.FromToRotation(spinAxis, Vector3.up);
            piw = rot * piw;

            float tFrac = TimeCoordScale(piw);
            SetEffectiveRadius(piw);

            // If interior, flip the metric signature between time-like and radial coordinates.
            float r = piw.magnitude;
            float tDiff = properTDiff;
            if (!isExterior)
            {
                piw = state.SpeedOfLight * state.TotalTimeWorld * piw / r;
                tDiff = -r;
            }

            // Get the angular frame-dragging velocity at the START of the finite difference time step.
            float omega = GetOmega(piw);
            float frameDragAngle = omega * tDiff;
            // We will apply HALF the rotation, at BOTH ends of the finite difference time interval.
            Quaternion frameDragRot = Quaternion.AngleAxis(frameDragAngle / 2.0f, spinAxis);

            // If interior... (reverse signature change).
            if (!isExterior)
            {
                piw = r * piw / (state.SpeedOfLight * state.TotalTimeWorld);
            }

            // Apply (half) the frame-dragging rotation.
            piw = frameDragRot * piw;
            riw = frameDragRot * riw;

            // Apply (full) Schwarzschild ComoveOptical() step.
            piw = Quaternion.Inverse(rot) * piw;
            Comovement forwardComovement = base.ComoveOptical(properTDiff, piw, riw);
            float tResult = tFrac * forwardComovement.piw.w;
            piw = forwardComovement.piw;
            piw = rot * piw;

            // If interior, flip the metric signature between time-like and radial coordinates.
            if (!isExterior)
            {
                piw = state.SpeedOfLight * state.TotalTimeWorld * piw / r;
                tDiff = -r;
            }

            // Get the angular frame-dragging velocity at the END of the finite difference time step.
            omega = GetOmega(piw);
            frameDragAngle = omega * tDiff;
            // We will apply HALF the rotation, at BOTH ends of the finite difference time interval.
            frameDragRot = Quaternion.AngleAxis(frameDragAngle / 2.0f, spinAxis);

            // If interior... (reverse signature change).
            if (!isExterior)
            {
                piw = r * piw / (state.SpeedOfLight * state.TotalTimeWorld);
            }

            piw = frameDragRot * piw;
            riw = frameDragRot * riw;

            ResetSchwarschildRadius();

            // Reverse spin axis rotation.
            piw = Quaternion.Inverse(rot) * piw;

            // Load the return object.
            forwardComovement.piw = new Vector4(piw.x, piw.y, piw.z, tResult);
            forwardComovement.riw = riw;

            return forwardComovement;
        }

        override public Vector3 GetRindlerAcceleration(Vector3 piw)
        {
            if ((spinMomentum <= SRelativityUtil.divByZeroCutoff) || (piw.sqrMagnitude <= SRelativityUtil.divByZeroCutoff))
            {
                return base.GetRindlerAcceleration(piw);
            }

            SetEffectiveRadius(piw);

            Quaternion rot = Quaternion.FromToRotation(spinAxis, Vector3.up);
            Vector3 lpiw = rot * piw;

            float r = lpiw.magnitude;
            if (!isExterior)
            {
                lpiw = state.SpeedOfLight * state.TotalTimeWorld * lpiw / r;
            }

            float omega = GetOmega(lpiw);
            Vector3 frameDragAccel = (omega * omega / lpiw.magnitude) * spinAxis;

            Vector3 totalAccel = frameDragAccel + base.GetRindlerAcceleration(piw);

            ResetSchwarschildRadius();

            return totalAccel;
        }

        override public void Update()
        {
            EnforceHorizon();

            if (schwarzschildRadius <= 0 || !doEvaporate || state.isMovementFrozen)
            {
                return;
            }

            float deltaR = deltaRadius;

            schwarzschildRadius += deltaR;

            if (schwarzschildRadius <= 0)
            {
                schwarzschildRadius = 0;
                spinMomentum = 0;
                return;
            }

            if (spinMomentum <= 0)
            {
                spinMomentum = 0;
                return;
            }

            // These happen to be equal:
            // float constRatio = state.planckAngularMomentum / state.planckLength;
            float constRatio = state.planckMomentum;

            float extremalFrac = spinMomentum / (schwarzschildRadius * constRatio);

            spinMomentum += extremalFrac * deltaR * constRatio;
        }
    }
}