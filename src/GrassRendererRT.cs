using UnityEngine;
using UnityEngine.Experimental.Rendering;
using System.Collections.Generic;


public partial class GrassRendererRT : MonoBehaviour
{
    private RenderTexture _initGrassTexture, _editGrassTexture, _HiZTex;
    private int _kernelInit;
    [SerializeField] private ComputeShader initCS, genCS;

    private ComputeBuffer _trianglesBuffer, _drawArgsBuffer;
    private int _kernelGen;
    private int _Time, _Wind, _PositionScale, _TextureHalfSize, _WorldSpaceCameraPos, _ViewProj, _CameraDepthTexture;

    [SerializeField] private int grassCountSqrt = 512;
    [SerializeField] private int maxBufferCount = 1024;
    [SerializeField] private Material grassMat;

    [SerializeField, Range(5f, 1000f)] private float spawnRadius;

    private const int VERTEX_DATA_SIZE = (1+3+3)*sizeof(float);
    private const int TRIANGLE_DATA_SIZE = 3*VERTEX_DATA_SIZE + 3*sizeof(float);

    private void OnEnable()
    {
        // Utils.Logger.Log($"ARGB4444: {SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGB32)}");
        // Utils.Logger.Log($"ARGB4444: {SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGB4444)}");
        // Utils.Logger.Log($"RGB565: {SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.RGB565)}");
        // Utils.Logger.Log($"ARGB2101010: {SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGB2101010)}");

        _initGrassTexture = new RenderTexture(grassCountSqrt, grassCountSqrt, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear)
        { enableRandomWrite = true };
        _editGrassTexture = new RenderTexture(grassCountSqrt, grassCountSqrt, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear)
        { enableRandomWrite = true };

        _kernelInit = initCS.FindKernel("CSInit");
        initCS.SetTexture(_kernelInit, "_InitGrass", _initGrassTexture);
        initCS.Dispatch(_kernelInit, grassCountSqrt/8, grassCountSqrt/8, 1);
        Graphics.CopyTexture(_initGrassTexture, _editGrassTexture);

        uint[] drawArgs = new uint[5] {0, 1, 0, 0, 0};
        _trianglesBuffer = new ComputeBuffer(maxBufferCount, TRIANGLE_DATA_SIZE, ComputeBufferType.Append);
        _drawArgsBuffer = new ComputeBuffer(1, drawArgs.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
        _drawArgsBuffer.SetData(drawArgs);

        _Time = Shader.PropertyToID("_Time");
        _Wind = Shader.PropertyToID("_Wind");
        _CameraDepthTexture = Shader.PropertyToID("_CameraDepthTexture");
        _PositionScale = Shader.PropertyToID("_PositionScale");
        _TextureHalfSize = Shader.PropertyToID("_TextureHalfSize");
        _WorldSpaceCameraPos = Shader.PropertyToID("_WorldSpaceCameraPos");
        _ViewProj = Shader.PropertyToID("_ViewProj");

        _kernelGen = genCS.FindKernel("Main");

        genCS.SetTexture(_kernelGen, "_EditGrass", _editGrassTexture);
        genCS.SetBuffer(_kernelGen, "_Triangles", _trianglesBuffer);
        genCS.SetBuffer(_kernelGen, "_IndirectArgsBuffer", _drawArgsBuffer);
        genCS.SetVector(_Wind, (Vector3.forward + Vector3.right).normalized);
        genCS.SetFloat(_PositionScale, spawnRadius / (grassCountSqrt * 0.5f));
        genCS.SetVector(_TextureHalfSize, new Vector2(grassCountSqrt, grassCountSqrt) * 0.5f);

        // >>> 
        // Utils.Logger.Log($"R8_SNorm: {SystemInfo.IsFormatSupported(GraphicsFormat.R8_SNorm, FormatUsage.Render)}");
        // Utils.Logger.Log($"R8_UNorm: {SystemInfo.IsFormatSupported(GraphicsFormat.R8_UNorm, FormatUsage.Render)}");
        // Utils.Logger.Log($"R16_SNorm: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_SNorm, FormatUsage.Render)}");
        // Utils.Logger.Log($"R16_UNorm: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_UNorm, FormatUsage.Render)}");
        // Utils.Logger.Log($"R16_SFloat - Render: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_SFloat, FormatUsage.Render)}");
        // Utils.Logger.Log($"R16_SFloat - Sample: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_SFloat, FormatUsage.Sample)}");
        // Utils.Logger.Log($"R16_SFloat - GetPixels: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_SFloat, FormatUsage.GetPixels)}");
        // Utils.Logger.Log($"R16_SFloat - LoadStore: {SystemInfo.IsFormatSupported(GraphicsFormat.R16_SFloat, FormatUsage.LoadStore)}");
        // Utils.Logger.Log($"Resolution: {Screen.currentResolution}");

        var res = new Vector2(Screen.currentResolution.width, Screen.currentResolution.height) / 16.0f;
        if (res.x < res.y) {
            (res.x, res.y) = (res.y, res.x);
        }
        _HiZTex = new RenderTexture(
            (int)res.x, 
            (int)res.y, 
            0, GraphicsFormat.R16_SFloat) {
            filterMode = FilterMode.Point,
            // enableRandomWrite = true,
        };
        // <<<

        genCS.SetTexture(_kernelGen, "_HiZTex", _HiZTex);
        genCS.SetVector("_HizTex_TexelSize", res);
        grassMat.SetBuffer("_Triangles", _trianglesBuffer);

        _grassCollisionInit();
        _grassCutInit();
    }

    private void Update()
    {
        Graphics.Blit(Shader.GetGlobalTexture(_CameraDepthTexture), _HiZTex);

        genCS.SetVector(_WorldSpaceCameraPos, Camera.main.transform.position);
        genCS.SetMatrix(_ViewProj, Camera.main.projectionMatrix * Camera.main.worldToCameraMatrix);
        genCS.SetFloat(_Time, Time.time);

        // // set args to zero
        _trianglesBuffer.SetCounterValue(0);
        GraphicsBuffer.CopyCount(_trianglesBuffer, _drawArgsBuffer, 0);
        _grassCollisionUpdate();
        _grassCutUpdate();
        genCS.Dispatch(_kernelGen, grassCountSqrt/8, grassCountSqrt/8, 1);

        // Graphics.DrawProceduralIndirect(grassMat, new Bounds(Vector3.zero, Vector3.one*1000f), MeshTopology.Triangles,
        //     _argsBuffer, 0, null, null, UnityEngine.Rendering.ShadowCastingMode.On, true, gameObject.layer);
        Graphics.DrawProceduralIndirect(grassMat, new Bounds(Vector3.zero, Vector3.one*1000f), MeshTopology.Triangles,
            _drawArgsBuffer, 0, null, null, UnityEngine.Rendering.ShadowCastingMode.Off, true, gameObject.layer);
    }

    private void OnDisable()
    {
        Destroy(_initGrassTexture);
        Destroy(_editGrassTexture);
        
        _trianglesBuffer?.Release();     _trianglesBuffer = null;
        _drawArgsBuffer?.Release();      _drawArgsBuffer = null;
    }
}


// collision
public partial class GrassRendererRT : MonoBehaviour
{
    private int _ColliderCountID, _ColliderArrayID;
    private const int MAX_COLLIDERS = 8;
    private int _ColliderCount;
    private readonly Vector4[] _ColliderArray = new Vector4[MAX_COLLIDERS];

    private void _grassCollisionInit()
    {
        _ColliderArrayID = Shader.PropertyToID("_Colliders");
        _ColliderCountID = Shader.PropertyToID("_ColliderCount");
    }
    private void _grassCollisionUpdate()
    {
        genCS.SetInt(_ColliderCountID, _ColliderCount);
        genCS.SetVectorArray(_ColliderArrayID, _ColliderArray);
        _ColliderCount = 0;    
    }

    private bool _addCollider(Vector3 position, float radius)
    {
        if (_ColliderCount >= MAX_COLLIDERS) return false;
        // _ColliderArray[_ColliderCount++] = new Vector4(position.x, position.y, position.z, radius*radius);
        _ColliderArray[_ColliderCount++] = new Vector4(position.x, position.y, position.z, radius);
        return true;
    }

    public class _GrassCollider : MonoBehaviour
    {
        [SerializeField] GrassRendererRT grassRenderer;
        public virtual float Radius { get; protected set; }

        protected void _addCollider()
        {
            // TODO: priority

            grassRenderer._addCollider(transform.position, Radius);
        }
    }
}


// cut
public partial class GrassRendererRT : MonoBehaviour
{
    [SerializeField] private ComputeShader editCS;
    private int _kernelEdit;

    private int _cutCountID, _cutArrayID;
    private const int MAX_CUTS = 8;
    private readonly Vector4[] _cutArrayDisp = new Vector4[MAX_CUTS];
    private readonly List<Vector4> _cutArray = new();

    private void _grassCutInit()
    {
        _cutCountID = Shader.PropertyToID("_ColliderCount");
        _cutArrayID = Shader.PropertyToID("_Colliders");

        _kernelEdit = editCS.FindKernel("Main");
        editCS.SetFloat(_PositionScale, spawnRadius / (grassCountSqrt * 0.5f));
        editCS.SetVector(_TextureHalfSize, new Vector2(grassCountSqrt, grassCountSqrt) * 0.5f);
        editCS.SetTexture(_kernelEdit, "_InitGrass", _initGrassTexture);
        editCS.SetTexture(_kernelEdit, "_EditGrass", _editGrassTexture);
    }

    private void _grassCutUpdate()
    {
        var realCount = _cutArray.Count;

        // while (realCount > 0) {  // execute in one frame
        if (realCount > 0) {  // execute in separated frames
            int dispCount;
            if (realCount >= MAX_CUTS) {
                dispCount = MAX_CUTS;
            } else {
                dispCount = realCount;
            }

            for (var i = 0; i < dispCount; i++) {
                _cutArrayDisp[i] = _cutArray[realCount-1];
                _cutArray.RemoveAt(realCount-1);
                realCount -= 1;
            }

            editCS.SetInt(_cutCountID, dispCount);
            editCS.SetVectorArray(_cutArrayID, _cutArrayDisp);
            editCS.Dispatch(_kernelEdit, grassCountSqrt/8, grassCountSqrt/8, 1);
            Graphics.CopyTexture(_editGrassTexture, _initGrassTexture);
            // Debug.Log($"Dispatch: {dispCount}");
        }
    }

    private void _addCutter(Vector3 position, float radius)
    {
        // TODO: callback
        _cutArray.Add(new Vector4(position.x, position.y, position.z, radius));
    }

    public class _GrassCutter : MonoBehaviour
    {
        private Vector3 _lastPosition;
        private float _lastRadius;
        [SerializeField] GrassRendererRT grassRenderer;
        [SerializeField] float cutSensitive = 0.1f;
        public virtual float Radius { get; protected set; }

        protected void _addCutter()
        {
            var pos = transform.position;
            if ((_lastPosition - pos).magnitude < cutSensitive && Mathf.Abs(_lastRadius - Radius) < cutSensitive) return;
            
            _lastPosition = pos;
            _lastRadius = Radius;
            grassRenderer._addCutter(pos, Radius);
        }
    }
}


// burn
public partial class GrassRendererRT : MonoBehaviour
{
}
