﻿using OpenRelativity.Objects;
using UnityEngine;

namespace Qrack
{
    public class TeleportAlice : RealTimeQasmProgram
    {
        public TeleportBob Bob;

        protected override void StartProgram()
        {

            ProgramInstructions.Add(new RealTimeQasmInstruction()
            {
                DeltaTime = 2.0f,
                quantumProgramUpdate = (x, y) =>
                {
                    QuantumSystem qs = QuantumSystem;
                    RelativisticObject ro = RelativisticObject;

                    qs.Rand(0);

                    float zProb = qs.Prob(0);
                    qs.H(0);
                    float xProb = qs.Prob(0);
                    qs.S(0);
                    float yProb = qs.Prob(0);
                    qs.Z(0);
                    qs.S(0);
                    qs.H(0);

                    HistoryPoints.Add(new QrackHistoryPoint
                    {
                        WorldTime = qs.LocalTime,
                        Action = (time) =>
                        {
                            ro.transform.eulerAngles = new Vector3(xProb * 360.0f, yProb * 360.0f, zProb * 360.0f);
                            ro.riw = qs.transform.rotation;
                        }
                    });

                    qs.MCX(new uint[] { 0 }, 1);
                    qs.H(0);
                }
            });

            ProgramInstructions.Add(new RealTimeQasmInstruction()
            {
                DeltaTime = 1.0f,
                quantumProgramUpdate = (x, y) =>
                {
                    QuantumSystem qs = QuantumSystem;
                    Bob.MeasurementResults[0] = qs.M(0);
                    Bob.MeasurementResults[1] = qs.M(1);
                }
            });
        }

    }
}
