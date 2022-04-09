using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class MoveableCamera : MonoBehaviour
{
    // https://forum.unity.com/threads/how-to-make-camera-move-in-a-way-similar-to-editor-scene.524645/
    [SerializeField] float navigationSpeed = 2.4f;
    [SerializeField] float shiftMultiplier = 2f;
    [SerializeField] float sensitivity = 1.0f;

    private Camera cam;
    private Vector3 anchorPoint;
    private Quaternion anchorRot;

    void Update()
    {
        Vector3 move = Vector3.zero;
        float speed = navigationSpeed * (Input.GetKey(KeyCode.LeftShift) ? shiftMultiplier : 1f) * Time.deltaTime * 9.1f;
        if (Input.GetKey(KeyCode.W)) move += Vector3.forward * speed;
        if (Input.GetKey(KeyCode.S)) move -= Vector3.forward * speed;
        if (Input.GetKey(KeyCode.D)) move += Vector3.right * speed;
        if (Input.GetKey(KeyCode.A)) move -= Vector3.right * speed;
        if (Input.GetKey(KeyCode.E)) move += Vector3.up * speed;
        if (Input.GetKey(KeyCode.Q)) move -= Vector3.up * speed;
        transform.Translate(move);

        if (Input.GetMouseButtonDown(1))
        {
            anchorPoint = new Vector3(Input.mousePosition.y, -Input.mousePosition.x);
            anchorRot = transform.rotation;
        }
        if (Input.GetMouseButton(1))
        {
            Quaternion rot = anchorRot;

            Vector3 dif = anchorPoint - new Vector3(Input.mousePosition.y, -Input.mousePosition.x);
            rot.eulerAngles += dif * sensitivity;
            transform.rotation = rot;
        }
    }
}
